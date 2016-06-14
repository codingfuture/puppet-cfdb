
# Done this way due to some weird behavior in tests also ignoring $LOAD_PATH
require File.expand_path( '../../../../puppet_x/cf_db', __FILE__ )

module Puppet::Parser::Functions
    newfunction(:cfdb_derived_port,  :type => :rvalue) do |args|
        raise(Puppet::ParseError,
            "cfdb_derived_port(base_port, derived_type): Wrong number of arguments " +
            "given (#{arguments.size} for 1)") if args.size != 2

        
        base_port = args[0]
        derived_type = args[1]
        
        return case derived_type
        when 'secure'
            base_port + PuppetX::CfDb::SECURE_PORT_OFFSET
        when 'galera'
            base_port + PuppetX::CfDb::MySQL::GALERA_PORT_OFFSET
        when 'galera_sst'
            base_port + PuppetX::CfDb::MySQL::SST_PORT_OFFSET
        when 'galera_ist'
            base_port + PuppetX::CfDb::MySQL::IST_PORT_OFFSET
        else
            raise(Puppet::ParseError,
                "cfdb_derived_port(): invalid derived port type #{derived_type}")
        end
    end
end
