
require File.expand_path( '../../../../puppet_x/cf_db', __FILE__ )

Puppet::Type.type(:cfdb_database).provide(
    :cfdb,
    :parent => PuppetX::CfDb::ProviderBase
) do
    desc "Provider for cfdb_database"
    
    mixin_dbtypes('database')
    
    commands :sudo => '/usr/bin/sudo'
    
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
end
