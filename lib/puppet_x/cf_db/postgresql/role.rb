#
# Copyright 2016-2019 (c) Andrey Galkin
#

require 'digest/md5'

module PuppetX::CfDb::PostgreSQL::Role
    include PuppetX::CfDb::PostgreSQL
    
    def create_postgresql(cluster_user, conf, root_dir)
        return if check_postgresql(cluster_user, conf, root_dir)
        
        cache = self.role_cache[cluster_user]
        user = conf[:user]
        pass = conf[:password]
        database = conf[:database]
        readonly = conf[:readonly]
        custom_grant = conf[:custom_grant]
        maxconn = conf[:allowed_hosts].values.inject(0, :+)
        
        oldconf = self.role_old.fetch(cluster_user, {}).fetch(user, {})
        grant_mismatch = (
            (oldconf.fetch(:custom_grant, nil) != custom_grant) ||
            (oldconf.fetch(:readonly, nil) != readonly)
        )
        database_mismatch = oldconf.fetch(:database, database) != database
        
        sql = []
        
        if cache.has_key? user
            cmd = 'ALTER'
            
            if grant_mismatch or database_mismatch
                sql += [
                    "REVOKE ALL PRIVILEGES ON DATABASE #{database} FROM #{user};",
                    "REVOKE ALL PRIVILEGES ON SCHEMA public FROM #{user};",
                    "REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM #{user};",
                    "REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public FROM #{user};",
                    "REVOKE ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public FROM #{user};",
                ]
            end
        else
            cmd = 'CREATE'
        end
        
        sql << [
                "#{cmd} ROLE #{user} WITH",
               "LOGIN ",
               "ENCRYPTED PASSWORD '#{pass}'",
               "CONNECTION LIMIT #{maxconn};"
            ].join(' ')
                
        if custom_grant
            gsql = custom_grant.gsub('$database', database).gsub('$user', user).split(';')
        elsif readonly
            gsql = [
                "GRANT CONNECT, TEMPORARY ON DATABASE #{database} TO #{user};",
                "GRANT USAGE ON SCHEMA public TO #{user};",
                "GRANT SELECT ON ALL TABLES IN SCHEMA public TO #{user};",
                "GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO #{user};",
                "GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO #{user};",
                "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO #{user};",
                "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON SEQUENCES TO #{user};",
                "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO #{user};",
            ]
        else
            gsql = [
                "GRANT ALL PRIVILEGES ON DATABASE #{database} TO #{user} WITH GRANT OPTION;",
                "GRANT ALL PRIVILEGES ON SCHEMA public TO #{user} WITH GRANT OPTION;",
                "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO #{user} WITH GRANT OPTION;",
                "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO #{user} WITH GRANT OPTION;",
                "GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO #{user} WITH GRANT OPTION;",
            ]
        end

        sql += gsql
        
        sql.each do |s|
            sudo("#{root_dir}/bin/cfdb_psql", '-c', s)
        end
    end
    
    def check_postgresql(cluster_user, conf, root_dir)
        if self.role_cache.has_key? cluster_user
            cache = self.role_cache[cluster_user]
        else
            ret = sudo(
                "#{root_dir}/bin/cfdb_psql",
                '--tuples-only', '--no-align', '--quiet',
                '--field-separator=,',
                '-c',
                'SELECT rolname, rolconnlimit, rolpassword FROM pg_authid ' +
                'WHERE rolsuper = FALSE AND rolreplication = FALSE AND rolcanlogin = TRUE;'
            )
            ret = ret.split("\n")
            cache = {}
            ret.each do |l|
                l = l.split(',')
                luser = l[0]
                maxconn = l[1]
                lpass = l[2]
                cache[luser] = {
                    :maxconn => maxconn.to_i,
                    :pass => lpass,
                }
            end
            
            self.role_cache[cluster_user] = cache
        end

        cache_user = cache[conf[:user]]
        return false if cache_user.nil?
        
        maxconn = conf[:allowed_hosts].values.inject(0, :+)
        return false if cache_user[:maxconn] != maxconn

        # note: this may change in the future
        conf_pass = conf[:password]
        return false if conf_pass.nil?
        conf_pass = 'md5' + Digest::MD5.hexdigest(conf_pass + conf[:user])
        return false if cache_user[:pass] != conf_pass
        
        self.check_match_common(cluster_user, conf)
    end
end
