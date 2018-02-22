#
# Copyright 2016-2018 (c) Andrey Galkin
#

require 'puppet/property/boolean'

Puppet::Type.newtype(:cfdb_haproxy_frontend) do
    desc "DO NOT USE DIRECTLY."
    
    VALID_PROXY_DB_TYPES = [
        'mysql',
        'postgresql',
        'elasticsearch',
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
    newproperty(:use_unix_socket, :boolean => true, :parent => Puppet::Property::Boolean)

    newproperty(:cluster_addr, :array_matching => :all) do
        desc "Known cluster addresses"
        
        validate do |value|
            (value.is_a? Hash and
                value.has_key? 'server' and
                value.has_key? 'addr' and
                value.has_key? 'port' and
                value.has_key? 'backup' and
                value.has_key? 'secure')
            
            value = munge value
        end
        
        munge do |value|
            return value if resource.should(:is_secure) or value['secure']
            begin
                ip = IPAddr.new(value['addr'])
            rescue
                ip = value['addr']

                unless ip =~ /^([a-zA-Z0-9]+)(\.[a-zA-Z0-9]+)*$/
                    raise ArgumentError, "%s is not valid DNS entry or IP4/6 address" % ip
                end
                
                begin
                    ip = Resolv.getaddress ip
                rescue
                    begin
                        # re-read /etc/hosts
                        ip = Resolv.new.getaddress ip
                    rescue
                        # leave DNS as-is
                    end
                end
            end
            
            value['addr'] = "#{ip}"
            value
        end
    end
    
    newproperty(:local_port) do
        validate do |value|
            unless value.is_a? Integer and value > 0
                raise ArgumentError, "%s is not valid local_port" % value
            end
        end
    end
end
