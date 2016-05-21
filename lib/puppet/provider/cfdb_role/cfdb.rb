
require 'ipaddr'
require 'resolv'

# Done this way due to some weird behavior in tests also ignoring $LOAD_PATH
begin
    require File.expand_path( '../../../../puppet_x/cf_system/provider_base', __FILE__ )
rescue LoadError
    require File.expand_path( '../../../../../../cfsystem/lib/puppet_x/cf_system/provider_base', __FILE__ )
end


Puppet::Type.type(:cfdb_role).provide(
    :cfdb,
    :parent => PuppetX::CfSystem::ProviderBase
) do
    desc "Provider for cfdb_role"
    
    commands :sudo => '/usr/bin/sudo'
    MYSQL = '/usr/bin/mysql' unless defined? MYSQL
    
    class << self
        # cfsystem.json config state
        # { cluster_user => { user => orig_params }
        attr_accessor :role_old
        # actual DB server config state
        # { cluster_user => { user => { allowed_hosts => max_connections } } }
        attr_accessor :role_cache
    end
    self.role_old = {}
    self.role_cache = {}
    
    def flush
        super
        title = "#{@resource[:cluster]}@#{@resource[:database]}"
        cf_system().config.get_persistent('cfdb_passwd')[title] = @resource[:password]
    end
    
    def self.check_exists(params)
        begin
            instance_index = Puppet::Type.type(:cfdb_instance).provider(:cfdb).get_config_index
            inst_conf = cf_system().config.get_old(instance_index)
            cluster = params[:cluster]
            inst_conf = inst_conf[cluster]
            cluster_user = inst_conf['user']
            db_type = inst_conf['type']
            
            self.role_old[cluster_user] = {} if not self.role_old.has_key? cluster_user
            self.role_old[cluster_user][params[:user]] = params
            
            begin
                self.send("check_#{db_type}", cluster_user, params)
            rescue => e
                warning(e)
                #warning(e.backtrace)
                err("Transition error in setup")
            end
        rescue => e
            warning(e)
            warning(e.backtrace)
            false
        end

    end
    
    def self.get_config_index
        'cf10db3_role'
    end

    def self.get_generator_version
        cf_system().makeVersion(__FILE__)
    end
    
    def self.on_config_change(newconf)
        to_delete = self.role_cache.clone
        
        instance_index = Puppet::Type.type(:cfdb_instance).provider(:cfdb).get_config_index
        inst_conf_all = cf_system().config.get_new(instance_index)
        
        cluster_type = {}
        
        newconf.each do |k, conf|
            cluster_name = conf[:cluster]
            inst_conf = inst_conf_all[cluster_name]
            cluster_user = inst_conf[:user]
            db_type = inst_conf[:type]
            
            begin
                self.send("create_#{db_type}", cluster_user, conf)
            rescue => e
                warning(e)
                #warning(e.backtrace)
                err("Transition error in setup")
            end
            
            if to_delete.has_key? cluster_user
                to_delete[cluster_user].delete conf[:user]
                cluster_type[cluster_user] = db_type
            end
        end
        
        to_delete.each do |cluster_user, cache|
            db_type = cluster_type[cluster_user]
            cache.each do |user, v|
                self.send("create_#{db_type}", cluster_user,
                {
                    :user => user,
                    :password => nil,
                    :allowed_hosts => {}
                })
            end
        end
    end
    
    #==================================
    def self.create_mysql(cluster_user, conf)
        return if check_mysql(cluster_user, conf)
        
        cache = self.role_cache[cluster_user]
        user = conf[:user]
        pass = conf[:password]
        database = conf[:database]
        custom_grant = conf[:custom_grant]
        allowed_hosts = conf[:allowed_hosts]
        
        to_remove = cache.fetch(user, {}).keys - allowed_hosts.keys
        sql = []
        
        oldconf = self.role_old.fetch(cluster_user, {}).fetch(user, {})
        grant_mismatch = oldconf.fetch(:custom_grant, nil) != custom_grant
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
            sudo('-u', cluster_user, MYSQL, '--wait', '-e', subsql.join(''))
        end
        
        # Final commands, if any
        if not sql.empty?
            sudo('-u', cluster_user, MYSQL, '--wait', '-e', sql.join(''))
        end
    end
    
    def self.check_mysql(cluster_user, conf)
        if self.role_cache.has_key? cluster_user
            cache = self.role_cache[cluster_user]
        else
            ret = sudo('-u', cluster_user,
                       MYSQL, '--wait', '--batch', '--skip-column-names', '-e',
                       'SELECT user, host, max_user_connections FROM mysql.user
                        WHERE Super_priv <> "Y" ORDER BY user, host;')
            ret = ret.split("\n")
            cache = {}
            ret.each do |l|
                l = l.split("\t")
                luser = l[0]
                next if luser == 'mysql.sys'
                lhost = l[1]
                maxconn = l[2]
                cache[luser] = {} if not cache.has_key? luser
                cache[luser][lhost] = maxconn.to_i
            end
            
            self.role_cache[cluster_user] = cache
        end
        
        user = conf[:user]
        
        oldconf = self.role_old.fetch(cluster_user, {}).fetch(user, {:custom_grant => nil})
        return false if oldconf[:custom_grant] != conf[:custom_grant]
        
        cache.fetch(user, {}) == conf[:allowed_hosts]
    end

    #==================================
    def self.create_postgresql(cluster_user, conf)
        return if check_postgresql(cluster_user, conf)
    end
    
    def self.check_postgresql(cluster_user, conf)
    end
end
