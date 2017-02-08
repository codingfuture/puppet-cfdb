#
# Copyright 2016-2017 (c) Andrey Galkin
#

Puppet::Type.newtype(:cfdb_role) do
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
    
    newproperty(:user) do
        validate do |value|
            unless value =~ /^[a-zA-Z_][a-zA-Z0-9_-]*$/
                raise ArgumentError, "%s is not valid user" % value
            end
        end
    end
    
    newproperty(:password) do
        validate do |value|
            unless value.is_a? String and value.length
                raise ArgumentError, "%s is not valid password" % value
            end
        end
        
        def is_to_s(value)
            return '<old_secret>'
        end

        def should_to_s(value)
            return '<new_secret>'
        end        
    end
    
    newproperty(:readonly, :boolean => true, :parent => Puppet::Property::Boolean)
    
    newproperty(:custom_grant) do
    end
    
    newproperty(:allowed_hosts) do
        validate do |value|
            unless value.is_a? Hash
                raise ArgumentError, "%s is not valid allowed_hosts" % value
            end
        end
        
        munge do |value|
            ret = {}
            
            value.each do |host, maxconn|
                begin
                    if host != 'localhost'
                        IPAddr.new(host)
                    end
                rescue
                    unless host =~ /^([a-zA-Z0-9]+)(\.[a-zA-Z0-9]+)*$/
                        raise ArgumentError, "%s is not valid DNS entry or IP4/6 address" % host
                    end
                    
                    begin
                        host = Resolv.getaddress host
                    rescue
                        begin
                            # re-read /etc/hosts
                            host = Resolv.new.getaddress host
                        rescue
                            # leave DNS as-is
                        end
                    end
                end
                
                ret[host] = maxconn
            end
            
            ret
        end
    end
end
