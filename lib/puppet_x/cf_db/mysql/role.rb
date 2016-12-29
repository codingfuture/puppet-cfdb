#
# Copyright 2016 (c) Andrey Galkin
#

require 'digest/sha1'

module PuppetX::CfDb::MySQL::Role
    include PuppetX::CfDb::MySQL
    
    def create_mysql(cluster_user, conf, root_dir)
        return if check_mysql(cluster_user, conf, root_dir)
        
        cache = self.role_cache[cluster_user]
        user = conf[:user]
        pass = conf[:password]
        database = conf[:database]
        readonly = conf[:readonly]
        custom_grant = conf[:custom_grant]
        allowed_hosts = conf[:allowed_hosts]
        
        to_remove = cache.fetch(user, {}).keys - allowed_hosts.keys
        sql = []
        
        oldconf = self.role_old.fetch(cluster_user, {}).fetch(user, {})
        grant_mismatch = (
            (oldconf.fetch(:custom_grant, nil) != custom_grant) ||
            (oldconf.fetch(:readonly, nil) != readonly)
        )
        database_mismatch = oldconf.fetch(:database, database) != database
        
        allowed_hosts.each do |host, maxconn|
            atomic_sql = []
            user_host = "'#{user}'@'#{host}'"
            atomic_sql << "CREATE USER #{user_host};" if not cache.fetch(user, {}).has_key? host
            
            # only in 5.7
            #atomic_sql << "ALTER USER #{user_host}
            #        IDENTIFIED BY '#{pass}'
            #        WITH MAX_USER_CONNECTIONS #{maxconn};"
            
            # for 5.6 compatibility
            atomic_sql << "SET PASSWORD FOR #{user_host} = PASSWORD('#{pass}');"
            atomic_sql << "GRANT USAGE ON #{database}.* TO #{user_host} WITH MAX_USER_CONNECTIONS #{maxconn};"

            if grant_mismatch or database_mismatch
                atomic_sql << "REVOKE ALL PRIVILEGES, GRANT OPTION FROM #{user_host};"
            end
                    
            if custom_grant
                atomic_sql << custom_grant.gsub('$database', database).gsub('$user', user_host)
            elsif readonly
                atomic_sql << "GRANT EXECUTE, SELECT ON #{database}.* TO #{user_host};"
            else
                atomic_sql << "GRANT ALL PRIVILEGES ON #{database}.* TO #{user_host};"
            end
            
            sql << atomic_sql.join('')
        end
        
        to_remove.each do |host|
            sql << "DROP USER '#{user}'@'#{host}';"
        end
        
        sql << 'FLUSH PRIVILEGES;'
        
        # Workaround possible hit of argument size limit
        while subsql = sql.slice!(0, 10) and !subsql.nil? and !subsql.empty?
            sudo('-H', '-u', cluster_user, MYSQL, '--wait', '-e', subsql.join(''))
        end
        
        # Final commands, if any
        if not sql.empty?
            sudo('-H', '-u', cluster_user, MYSQL, '--wait', '-e', sql.join(''))
        end
    end
    
    def check_mysql(cluster_user, conf, root_dir)
        if self.role_cache.has_key? cluster_user
            cache = self.role_cache[cluster_user]
        else
            begin
                # before v5.7
                ret = sudo('-H', '-u', cluster_user,
                       MYSQL, '--wait', '--batch', '--skip-column-names', '-e',
                       'SELECT User, Host, max_user_connections, Password FROM mysql.user
                        WHERE Super_priv <> "Y" ORDER BY user, host;')
            rescue
                # v5.7
                ret = sudo('-H', '-u', cluster_user,
                       MYSQL, '--wait', '--batch', '--skip-column-names', '-e',
                       'SELECT User, Host, max_user_connections, authentication_string FROM mysql.user
                        WHERE Super_priv <> "Y" ORDER BY user, host;')
            end
            
            ret = ret.split("\n")
            cache = {}
            ret.each do |l|
                l = l.split("\t")
                luser = l[0]
                next if luser == 'mysql.sys'
                lhost = l[1]
                maxconn = l[2]
                lpass = l[3]
                cache[luser] = {} if not cache.has_key? luser
                cache[luser][lhost] = {
                    :maxconn => maxconn.to_i,
                    :pass => lpass,
                }
            end
            
            self.role_cache[cluster_user] = cache
        end
        
        cache_user = cache[conf[:user]]
        return false if cache_user.nil?
        
        conf_pass = conf[:password]
        return false if conf_pass.nil?
        conf_pass = '*' + Digest::SHA1.hexdigest(Digest::SHA1.digest(conf_pass)).upcase
        found_hosts = {}

        cache_user.each do |h, hinfo|
            return false if hinfo[:pass] != conf_pass
            found_hosts[h] = hinfo[:maxconn]
        end
        
        return false if found_hosts != conf[:allowed_hosts]
        
        self.check_match_common(cluster_user, conf)
    end
end
