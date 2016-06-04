
# Done this way due to some weird behavior in tests also ignoring $LOAD_PATH
begin
    require File.expand_path( '../../../../puppet_x/cf_system/provider_base', __FILE__ )
rescue LoadError
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
            instance_index = Puppet::Type.type(:cfdb_instance).provider(:cfdb).get_config_index
            inst_conf = cf_system().config.get_old(instance_index)
            cluster = params[:cluster]

            inst_conf = inst_conf[cluster]
            return false if inst_conf.nil?

            db_type = inst_conf['type']
            self.send("check_#{db_type}", inst_conf['user'], params[:database], inst_conf['root_dir'])
        rescue => e
            warning(e)
            #warning(e.backtrace)
            false
        end
    end
    
    def self.get_config_index
        'cf10db2_database'
    end

    def self.get_generator_version
        cf_system().makeVersion(__FILE__)
    end
    
    def self.on_config_change(newconf)
        instance_index = Puppet::Type.type(:cfdb_instance).provider(:cfdb).get_config_index
        inst_conf_all = cf_system().config.get_new(instance_index)
        
        newconf.each do |k, conf|
            inst_conf = inst_conf_all[conf[:cluster]]
            db_type = inst_conf[:type]
            begin
                self.send("create_#{db_type}", inst_conf[:user], conf[:database], inst_conf[:root_dir])
            rescue => e
                warning(e)
                #warning(e.backtrace)
                err("Transition error in setup")
            end
        end
    end
    
    #==================================
    def self.create_mysql(user, database, root_dir)
        return if check_mysql(user, database, root_dir)
        sudo('-u', user, MYSQLADMIN, 'create', database)
    end
    
    def self.check_mysql(user, database, root_dir)
        ret = sudo('-u', user, MYSQL, '--wait', '-e', "SHOW DATABASES LIKE '#{database}';")
        not ret.empty?
    end

    #==================================
    def self.create_postgresql(user, database, root_dir)
        return if check_postgresql(user, database, root_dir)
        sudo("#{root_dir}/bin/cfdb_psql",
             '--tuples-only', '--no-align', '--quiet',
             '-c', "CREATE DATABASE #{database} TEMPLATE template0;")
    end
    
    def self.check_postgresql(user, database, root_dir)
        ret = sudo(
            "#{root_dir}/bin/cfdb_psql",
            '--tuples-only', '--no-align', '--quiet',
            '-c', "SELECT datname FROM pg_database WHERE datname = '#{database}';"
        )
        not ret.empty?
    end
end
