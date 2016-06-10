
require File.expand_path( '../../../../puppet_x/cf_db', __FILE__ )

Puppet::Type.type(:cfdb_haproxy_backend).provide(
    :cfdb,
    :parent => PuppetX::CfDb::ProviderBase
) do
    desc "Provider for cfdb_haproxy_backend"
    
    commands :sudo => '/usr/bin/sudo'
    
    def self.get_config_index
        'cf20db2_haproxy_backend'
    end

    def self.get_generator_version
        cf_system().makeVersion(__FILE__)
    end

    def self.on_config_change(newconf)
        # noop - only store in cfsystem.json
    end
end
