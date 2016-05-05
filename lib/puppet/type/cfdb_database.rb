Puppet::Type.newtype(:cfdb_database do
    desc "DO NOT USE DIRECTLY."
    
    autorequire(:cfdb_instance) do
        [should(:name)]
    end
    
    ensurable do
        defaultvalues
        defaultto :absent
    end
    
    newparam(:name) do
        isnamevar
    end

    newproperty(:cluster_name) do
        validate do |value|
            unless value =~ /^[a-zA-Z_][a-zA-Z0-9_-]*$/
                raise ArgumentError, "%s is not valid cluster_name" % value
            end
        end
    end
    
    newproperty(:db_name) do
        validate do |value|
            unless value =~ /^[a-zA-Z_][a-zA-Z0-9_-]*$/
                raise ArgumentError, "%s is not valid db_name" % value
            end
        end
    end
end
