
# Done this way due to some weird behavior in tests also ignoring $LOAD_PATH
require File.expand_path( '../../../../puppet_x/cf_system/provider_base', __FILE__ )

Puppet::Type.type(:cfdb_database).provide(
    :cfdb,
    :parent => PuppetX::CfSystem::ProviderBase
) do
    desc "Provider for cfdb_database"
    
    commands :sudo => '/usr/bin/sudo'
    MYSQL = '/usr/bin/mysql'
    MYSQLADMIN = '/usr/bin/mysqladmin'
    
    def self.check_exists(params)
        begin
            inst_conf = cf_system().config.get_old('cfdb_instance')
            inst_conf = inst_conf[params[:cluster_name]]
            db_type = inst_conf[:type]
            self.send("check_#{db_type}", inst_conf[:user], params[:db_name])
        rescue
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
        newconf.each do |k, conf|
            inst_conf = cf_system().config.get_new('cfdb_instance')
            inst_conf = inst_conf[conf[:cluster_name]]
            db_type = inst_conf[:type]
            self.send("create_#{db_type}", inst_conf[:user], conf[:db_name])
        end
    end
    
    #==================================
    def self.create_mysql(user, db_name)
        return if check_mysql(user, db_name)
        sudo('-u', user, MYSQLADMIN, 'create', db_name)
    end
    
    def self.check_mysql(user, db_name)
        ret = sudo('-u', user, MYSQL, '-e', "SHOW DATABASES LIKE '#{db_name}';")
        not ret.empty?
    end

    #==================================
    def self.create_postgresql(user, db_name)
        return if check_postgresql(user, db_name)
    end
    
    def self.check_postgresql(user, db_name)
    end
end
