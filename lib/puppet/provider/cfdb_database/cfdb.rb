
# Done this way due to some weird behavior in tests also ignoring $LOAD_PATH
begin
    require File.expand_path( '../../../../puppet_x/cf_system/provider_base', __FILE__ )
rescue
    require File.expand_path( '../../../../../../cfsystem/lib/puppet_x/cf_system/provider_base', __FILE__ )
end



Puppet::Type.type(:cfdb_database).provide(
    :cfdb,
    :parent => PuppetX::CfSystem::ProviderBase
) do
    desc "Provider for cfdb_database"
    
    commands :sudo => '/usr/bin/sudo'
    MYSQL = '/usr/bin/mysql' unless defined? MYSQL
    MYSQLADMIN = '/usr/bin/mysqladmin' unless defined? MYSQLADMIN
    
    def self.check_exists(params)
        begin
            inst_conf = cf_system().config.get_old('cfdb_instance')
            inst_conf = inst_conf[params[:cluster]]
            db_type = inst_conf['type']
            self.send("check_#{db_type}", inst_conf['user'], params[:database])
        rescue => e
            warning(e)
            false
        end
    end
    
    def self.get_config_index
        'cfdb_database'
    end

    def self.get_generator_version
        cf_system().makeVersion(__FILE__)
    end
    
    def self.on_config_change(newconf)
        inst_conf_all = cf_system().config.get_new('cfdb_instance')
        
        newconf.each do |k, conf|
            inst_conf = inst_conf_all[conf[:cluster]]
            db_type = inst_conf[:type]
            self.send("create_#{db_type}", inst_conf[:user], conf[:database])
        end
    end
    
    #==================================
    def self.create_mysql(user, database)
        return if check_mysql(user, database)
        sudo('-u', user, MYSQLADMIN, 'create', database)
    end
    
    def self.check_mysql(user, database)
        ret = sudo('-u', user, MYSQL, '-e', "SHOW DATABASES LIKE '#{database}';")
        not ret.empty?
    end

    #==================================
    def self.create_postgresql(user, database)
        return if check_postgresql(user, database)
    end
    
    def self.check_postgresql(user, database)
    end
end
