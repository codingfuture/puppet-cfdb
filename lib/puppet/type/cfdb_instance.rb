#
# Copyright 2016-2018 (c) Andrey Galkin
#

require 'puppet/property/boolean'

Puppet::Type.newtype(:cfdb_instance) do
    desc "DO NOT USE DIRECTLY."
    
    VALID_DB_TYPES = [
        'mysql',
        'postgresql',
    ] unless defined? VALID_DB_TYPES
    
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
    newproperty(:is_bootstrap, :boolean => true, :parent => Puppet::Property::Boolean)
    newproperty(:is_arbitrator, :boolean => true, :parent => Puppet::Property::Boolean)
    
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
    
    newproperty(:backup_dir) do
        validate do |value|
            unless value =~ /^(\/[a-z0-9_]+)+$/i
                raise ArgumentError, "%s is not a valid path" % value
            end
        end
    end
    
    newproperty(:settings_tune) do
        validate do |value|
            value.is_a? Hash
        end
        
        munge do |value|
            value.each do |section, info|
                # a workaround for seems to be buggy Puppet merge()
                info.each do |k, v|
                    if v == 'undef'
                        info.delete k
                    end
                end
            end
        end
        
        
        def is_to_s(value)
            srepr = value.to_s
            srepr.gsub!(value.fetch('cfdb', {}).fetch('shared_secret', 'some pass'), '<secret>')
            return srepr
        end

        def should_to_s(value)
            is_to_s value
        end        
    end
    
    newproperty(:service_name) do
        validate do |value|
            unless value =~ /^[a-z0-9_@-]+$/i
                raise ArgumentError, "%s is not a valid service name" % value
            end
        end
    end
    
    newproperty(:version) do
        validate do |value|
            value.is_a? String
        end
    end
    
    newproperty(:cluster_addr, :array_matching => :all) do
        desc "Known cluster addresses"
        
        validate do |value|
            # we need proper commonName
            return if resource.should(:settings_tune).fetch('cfdb', {}).fetch('secure_cluster', false)
            
            value = munge value
        end
        
        munge do |value|
            # we need proper commonName
            return value if resource.should(:settings_tune).fetch('cfdb', {}).fetch('secure_cluster', false)
            
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
    
    newproperty(:access_list) do
        validate do |value|
            value.is_a? Hash
        end
    end

    newproperty(:location) do
        validate do |value|
            value.is_a? String
        end
    end
end
