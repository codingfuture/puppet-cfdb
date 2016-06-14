
require File.expand_path( '../../../../puppet_x/cf_db', __FILE__ )


Puppet::Type.type(:cfdb_access).provide(
    :cfdb,
    :parent => PuppetX::CfDb::ProviderBase
) do
    desc "Provider for cfdb_access"
    
    commands :sudo => '/usr/bin/sudo'
    CFDB_HEALTH_CHECK = 'cfdbhealth'
    
    def self.get_config_index
        'cf10db4_access'
    end

    def self.get_generator_version
        cf_system().makeVersion(__FILE__)
    end
    
    def self.check_exists(params)
        debug('check_exists')
        begin
            return true if params[:role] == CFDB_HEALTH_CHECK
            
            config_info = params[:config_info]
            
            sudo(PuppetX::CfDb::ACCESS_CHECK_TOOL,
                params[:local_user],
                config_info['dotenv'],
                config_info['prefix']
            )
        
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
                next if conf[:role] == CFDB_HEALTH_CHECK
                
                config_info = conf[:config_info]
                
                sudo(PuppetX::CfDb::ACCESS_CHECK_TOOL,
                    conf[:local_user],
                    config_info['dotenv'],
                    config_info['prefix']
                )
            rescue => e
                warning(e)
                #warning(e.backtrace)
                err("Transition error in setup")
            end
        end
    end
end
