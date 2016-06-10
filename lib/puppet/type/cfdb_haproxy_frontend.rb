require 'puppet/property/boolean'

Puppet::Type.newtype(:cfdb_haproxy_frontend) do
    desc "DO NOT USE DIRECTLY."
    
    VALID_PROXY_DB_TYPES = [
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
            unless VALID_PROXY_DB_TYPES.include? value
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
    newproperty(:socket) do
    end
    newproperty(:role) do
    end
    newproperty(:password) do
    end
    
    newproperty(:access_user) do
    end
    
    newproperty(:max_connections) do
        validate do |value|
            unless value.is_a? Integer and value > 0
                raise ArgumentError, "%s is not valid max_connections" % value
            end
        end
    end
    
    newproperty(:is_secure, :boolean => true, :parent => Puppet::Property::Boolean)
    newproperty(:distribute_load, :boolean => true, :parent => Puppet::Property::Boolean)

    newproperty(:cluster_addr, :array_matching => :all) do
        desc "Known cluster addresses"
        
        validate do |value|
            (value.is_a? Hash and
                value.has_key? 'server' and
                value.has_key? 'addr' and
                value.has_key? 'port' and
                value.has_key? 'backup' and
                value.has_key? 'secure')
            
            return if resource.should(:is_secure) or value['secure']
            
            value = munge value
            ip = IPAddr.new(value['addr']) # may raise ArgumentError

            unless ip.ipv4? or ip.ipv6?
                raise ArgumentError, "%s is not a valid IPv4 or IPv6 address" % value
            end
        end
        
        munge do |value|
            return value if resource.should(:is_secure) or value['secure']
            begin
                ip = IPAddr.new(value['addr'])
            rescue
                ip = Resolv.getaddress res[0]
            end
            
            value['addr'] = "#{ip}"
            value
        end
    end
end
