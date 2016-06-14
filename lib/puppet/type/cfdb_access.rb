Puppet::Type.newtype(:cfdb_access) do
    desc "DO NOT USE DIRECTLY."
    
    autorequire(:cfsystem_flush_config) do
        ['begin']
    end
    autonotify(:cfsystem_flush_config) do
        ['commit']
    end
    
    ensurable do
        defaultvalues
        defaultto :absent
    end
    
    newparam(:name) do
        isnamevar
    end

    newproperty(:cluster) do
        validate do |value|
            unless value =~ /^[a-zA-Z_][a-zA-Z0-9_-]*$/
                raise ArgumentError, "%s is not valid cluster" % value
            end
        end
    end
    
    newproperty(:role) do
        validate do |value|
            unless value =~ /^[a-zA-Z_][a-zA-Z0-9_-]*$/
                raise ArgumentError, "%s is not valid role" % value
            end
        end
    end
    
    newproperty(:local_user) do
        validate do |value|
            unless value =~ /^[a-zA-Z_][a-zA-Z0-9_-]*$/
                raise ArgumentError, "%s is not valid user" % value
            end
        end
    end

    newproperty(:max_connections) do
        validate do |value|
            unless value.is_a? Integer and value > 0
                raise ArgumentError, "%s is not vakud max_connections" % value
            end
        end
    end
    
    newproperty(:client_host) do
    end
    
    newproperty(:config_info) do
        validate do |value|
            value.is_a? Hash
        end
    end    
end
