#
# Copyright 2016-2019 (c) Andrey Galkin
#

require File.expand_path( '../../../../puppet_x/cf_db', __FILE__ )

Puppet::Functions.create_function(:'cfdb::derived_port') do
    dispatch :derived_port do
        param 'Cfnetwork::Port', :base_port
        param "String[1]", :derived_type
    end
    
    def derived_port(base_port, derived_type)
        return case derived_type
        when 'secure'
            base_port + PuppetX::CfDb::SECURE_PORT_OFFSET
        when 'galera'
            base_port + PuppetX::CfDb::MySQL::GALERA_PORT_OFFSET
        when 'galera_sst'
            base_port + PuppetX::CfDb::MySQL::SST_PORT_OFFSET
        when 'galera_ist'
            base_port + PuppetX::CfDb::MySQL::IST_PORT_OFFSET
        when 'elasticsearch'
            base_port + PuppetX::CfDb::Elasticsearch::CLUSTER_PORT_OFFSET
        else
            raise(Puppet::ParseError,
                "cfdb::derived_port(): invalid derived port type #{derived_type}")
        end
    end
end
