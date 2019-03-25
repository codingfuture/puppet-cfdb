#
# Copyright 2019 (c) Andrey Galkin
#


module PuppetX::CfDb::MongoDB::Role
    include PuppetX::CfDb::MongoDB
    
    
    def create_mongodb(cluster_user, conf, root_dir)
        return if check_mongodb(cluster_user, conf, root_dir)

        user = conf[:user]
        pass = conf[:password]
        database = conf[:database]
        readonly = conf[:readonly]
        custom_grant = conf[:custom_grant] || []
        allowed_hosts = conf[:allowed_hosts]

        cache = self.role_cache[cluster_user]
        
        oldconf = self.role_old.fetch(cluster_user, {}).fetch(user, {})
        mismatch = (
            (oldconf.fetch(:custom_grant, []).to_json != custom_grant.to_json) ||
            (oldconf.fetch(:readonly, nil) != readonly) ||
            (oldconf.fetch(:database, database) != database)
        )

        cmd = [
            "const tdb = db.getMongo().getDB('#{database}');"
        ]

        role = readonly ? 'read' : 'readWrite'
        roles = [role]
        roles += custom_grant

        # A small hack...
        if user == 'cfdbhealth'
            roles << {
                'db' => 'admin',
                'role' => 'clusterMonitor',
            }
        end

        user_info = {
            'pwd' => pass,
            'roles' => roles,
            #'authenticationRestrictions' => [
            #    {
            #        clientSource: allowed_hosts.keys,
            #    },
            #]
        }

        if pass.nil?
            cmd << "tdb.dropUser('#{user}');"
        elsif cache.has_key? user
            cmd << "tdb.updateUser('#{user}', #{user_info.to_json});"
        else
            user_info['user'] = user
            cmd << "tdb.createUser(#{user_info.to_json});"
        end
        cmd << "printjson(tdb.getUser('#{user}', {showCredentials: true}))"

        tmp_exec_file = "#{root_dir}/tmp/confuser.js"
        cf_system.atomicWrite(tmp_exec_file, cmd, {:user => cluster_user, :silent => true})

        res = sudo('-H', '-u', cluster_user,
            MONGO, '--host', "#{root_dir}/server.sock",
            '--quiet',
            'admin',
            "#{root_dir}/.mongorc.js",
            tmp_exec_file).split("\n").drop(2)

        while res.size > 1 and res[0] != '{'
            res = res.drop(1)
        end

        res = JSON.parse(res.join("\n"))
        hash_cache = conf[:cache] || {}
        res['credentials'].each { |k, v|
            hash_cache[k] = v['storedKey']
        }
        conf[:cache] = hash_cache
    end
    
    def check_mongodb(cluster_user, conf, root_dir)
        database = conf[:database]

        if self.role_cache_misc.include?(database) and self.role_cache.has_key? cluster_user
            cache = self.role_cache[cluster_user]
        else
            tmp_exec_file = "#{root_dir}/tmp/listusers.js"
            cmd = [
                "let tdb = db.getMongo().getDB('#{database}');",
                'printjson(tdb.getUsers({showCredentials: true}))',
            ]
            cf_system.atomicWrite(tmp_exec_file, cmd, {:user => cluster_user, :silent => true})
            
            res = sudo('-H', '-u', cluster_user,
                MONGO, '--host', "#{root_dir}/server.sock",
                '--quiet',
                'admin',
                "#{root_dir}/.mongorc.js",
                tmp_exec_file).split("\n").drop(2).join("\n")
            
            
            res = JSON.parse(res)
            cache = self.role_cache.fetch(cluster_user, {})

            res.each do |v|
                luser = v['user']
                ldb = v['database']
                next if ['admin', 'local', 'config', '$external'].include? ldb

                cache[luser] = {
                    :database => ldb,
                    :pass => v['credentials'],
                    :roles => v['roles'],
                }
            end
            
            self.role_cache[cluster_user] = cache
            self.role_cache_misc << database
        end

        luser = conf[:user]
        cache_user = cache[luser]
        return false if cache_user.nil?
        
        conf_pass = conf[:password]
        return false if conf_pass.nil?

        cache_user[:pass].each do |ht, htinfo|
            if (conf[:cache] || {}).has_key? ht
                hash_pass = conf[:cache][ht]
            else
                return false
            end

            if hash_pass != htinfo['storedKey']
                warning("> #{conf[:user]} password mismatch #{hash_pass} != #{htinfo['storedKey']}")
                return false
            end
        end
        
        self.check_match_common(cluster_user, conf)
    end
end
