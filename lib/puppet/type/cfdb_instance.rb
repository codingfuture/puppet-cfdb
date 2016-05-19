require 'puppet/property/boolean'

Puppet::Type.newtype(:cfdb_instance) do
    desc "DO NOT USE DIRECTLY."
    
    VALID_DB_TYPES = [
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

    newproperty(:type) do
        validate do |value|
            unless VALID_DB_TYPES.include? value
                raise ArgumentError, "%s is not valid username" % value
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
    newproperty(:user) do
        validate do |value|
            unless value =~ /^[a-zA-Z_][a-zA-Z0-9_-]*$/
                raise ArgumentError, "%s is not valid user" % value
            end
        end
    end
   
    
    newproperty(:is_cluster, :boolean => true, :parent => Puppet::Property::Boolean)
    newproperty(:is_secondary, :boolean => true, :parent => Puppet::Property::Boolean)
    
    newproperty(:memory_weight) do
        validate do |value|
            unless value.is_a? Integer and value > 0
                raise ArgumentError, "%s is not a valid positive integer" % value
            end
        end
    end

    newproperty(:cpu_weight) do
        validate do |value|
            unless value.is_a? Integer and value > 0
                raise ArgumentError, "%s is not a valid positive integer" % value
            end
        end
    end
    
    newproperty(:io_weight) do
        validate do |value|
            unless value.is_a? Integer and value > 0
                raise ArgumentError, "%s is not a valid positive integer" % value
            end
        end
    end
    
    newproperty(:target_size) do
        validate do |value|
            unless value == 'auto' or (value.is_a? Integer and value > 0)
                raise ArgumentError, "%s is not a valid positive integer" % value
            end
        end
    end
    
    newproperty(:root_dir) do
        validate do |value|
            unless value =~ /^(\/[a-z0-9_]+)+$/i
                raise ArgumentError, "%s is not a valid path" % value
            end
        end
    end
    
    newproperty(:settings_tune) do
    end
    
    newproperty(:service_name) do
        validate do |value|
            unless value =~ /^[a-z0-9_@-]+$/i
                raise ArgumentError, "%s is not a valid service name" % value
            end
        end
    end
    
    newproperty(:cluster_addr, :array_matching => :all) do
        desc "Known cluster addresses"
        
        validate do |value|
            value = munge value
            res = value.split(':')
            ip = IPAddr.new(res[0]) # may raise ArgumentError

            unless ip.ipv4? or ip.ipv6?
                raise ArgumentError, "%s is not a valid IPv4 or IPv6 address" % value
            end
        end
        
        munge do |value|
            res = value.split(':')
            
            begin
                ip = IPAddr.new(res[0])
                "#{ip}:#{res[1]}"
            rescue
                ip = Resolv.getaddress res[0]
                "#{ip}:#{res[1]}"
            end
        end
    end
end
