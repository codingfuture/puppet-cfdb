#
# Copyright 2016-2017 (c) Andrey Galkin
#

Puppet::Type.newtype(:cfdb_database) do
    desc "DO NOT USE DIRECTLY."
    
    autorequire(:cfsystem_flush_config) do
        ['begin']
    end
    autonotify(:cfsystem_flush_config) do
        ['commit']
    end
   
    autorequire(:cfdb_instance) do
        [should(:cluster)]
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
    
    newproperty(:database) do
        validate do |value|
            unless value =~ /^[a-zA-Z_][a-zA-Z0-9_-]*$/
                raise ArgumentError, "%s is not valid database" % value
            end
        end
    end
    
    newproperty(:ext, :array_matching => :all) do
        desc "Type-specific database extensions to create"
        
        validate do |value|
            value.is_a? String
        end
    end
end
