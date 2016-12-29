#
# Copyright 2016 (c) Andrey Galkin
#

require 'puppet/property/boolean'

Puppet::Type.newtype(:cfdb_haproxy_endpoint) do
    desc "DO NOT USE DIRECTLY."
    
    VALID_ENDPOINT_DB_TYPES = [
        'mysql',
        'postgresql',
    ]
    
    autorequire(:cfsystem_flush_config) do
        ['begin']
    end
    autorequire(:cfsystem_memory_calc) do
        ['total']
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
    
    newproperty(:listen) do
    end
    
    newproperty(:sec_port) do
    end

    newproperty(:service_name) do
        validate do |value|
            unless value =~ /^[a-z0-9_@-]+$/i
                raise ArgumentError, "%s is not a valid service name" % value
            end
        end
    end

    newproperty(:type) do
        validate do |value|
            unless VALID_ENDPOINT_DB_TYPES.include? value
                raise ArgumentError, "%s is not valid db type" % value
            end
        end
    end

    newproperty(:cluster) do
        validate do |value|
            unless value =~ /^[a-zA-Z_][a-zA-Z0-9_-]*$/
                raise ArgumentError, "%s is not valid cluster" % value
            end
        end
    end
    
    newproperty(:max_connections) do
        validate do |value|
            unless value.is_a? Integer and value > 0
                raise ArgumentError, "%s is not valid max_connections" % value
            end
        end
    end
end
