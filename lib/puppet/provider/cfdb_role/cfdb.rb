
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
        attr_accessor :role_cache
    end
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
            inst_conf = inst_conf[params[:cluster]]
            db_type = inst_conf['type']
            self.send("check_#{db_type}", inst_conf['user'], params)
        rescue => e
            warning(e)
            false
        end

    end
    
    def self.get_config_index
        'cfdb3_role'
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
            
            self.send("create_#{db_type}", cluster_user, conf)
            
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
        allowed_hosts = conf[:allowed_hosts]
        to_remove = cache[user].keys - allowed_hosts.keys
        sql = []
        
        allowed_hosts.each do |host, maxconn|
            sql << "CREATE USER IF NOT EXISTS #{user}@#{host};"
            sql << "ALTER USER #{user}@#{host}
                    IDENTIFIED BY '#{pass}'
                    WITH MAX_USER_CONNECTIONS #{maxconn};"
        end
        
        to_remove.each do |host|
            sql << "DROP USER #{user}@#{host};"
        end
        
        sql << 'FLUSH PRIVILEGES;'
        
        # Workaround possible hit of argument size limit
        while subsql = sql.slice!(0, 10)
            sudo('-u', cluster_user, MYSQL, '--wait', '-e', subsql.join(''))
        end
        
        # Final commands, if any
        if not sql.empty?
            sudo('-u', cluster_user, MYSQL, '--wait', '-e', sql.join(''))
        end
    end
    
    def self.check_mysql(cluster_user, conf)
        if not self.role_cache.has_key? cluster_user
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
        else
            cache = self.role_cache[cluster_user]
        end
        
        user = conf[:user]
        cache[user] = {} if not cache.has_key? user
        
        cache[user] == conf[:allowed_hosts]
    end

    #==================================
    def self.create_postgresql(cluster_user, conf)
        return if check_postgresql(cluster_user, conf)
    end
    
    def self.check_postgresql(cluster_user, conf)
    end
end
