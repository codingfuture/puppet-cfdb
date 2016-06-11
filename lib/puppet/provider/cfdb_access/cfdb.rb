
require File.expand_path( '../../../../puppet_x/cf_db', __FILE__ )


Puppet::Type.type(:cfdb_access).provide(
    :cfdb,
    :parent => PuppetX::CfDb::ProviderBase
) do
    desc "Provider for cfdb_access"
    
    mixin_dbtypes('access')
    
    commands :sudo => '/usr/bin/sudo'
    
    def self.get_config_index
        'cf10db4_access'
    end

    def self.get_generator_version
        cf_system().makeVersion(__FILE__)
    end
    
    def self.check_exists(params)
        debug('check_exists')
        begin
            config_vars = params[:config_vars]
            db_type = config_vars['type']
            self.send("check_#{db_type}", params[:local_user], config_vars)
        rescue => e
            warning(e)
            #warning(e.backtrace)
            false
        end
    end

    def self.on_config_change(newconf)
        debug('on_config_change')
        newconf.each do |name, conf|
            begin
                config_vars = conf[:config_vars]
                db_type = config_vars['type']
                self.send("check_#{db_type}", conf[:local_user], config_vars)
            rescue => e
                warning(e)
                #warning(e.backtrace)
                err("Transition error in setup")
            end
        end
    end
end
