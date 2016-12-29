#
# Copyright 2016 (c) Andrey Galkin
#

require 'json'

# Done this way due to some weird behavior in tests also ignoring $LOAD_PATH
begin
    require File.expand_path( '../../puppet_x/cf_system', __FILE__ )
rescue LoadError
    require File.expand_path( '../../../../cfsystem/lib/puppet_x/cf_system', __FILE__ )
end

Facter.add('cfdbaccess') do
    setcode do
        cfsystem_json = PuppetX::CfSystem::CFSYSTEM_CONFIG
        begin
            json = File.read(cfsystem_json)
            json = JSON.parse(json)
            sections = json['sections']
            persistent = json['persistent']['ports']
            
            ret = {}
            
            sections['cf10db4_access'].each do |k, info|
                cluster = info['cluster']
                role = info['role']
                
                if not ret.has_key? cluster
                    ret[cluster] = {
                        'roles' => {},
                        'present' => true,
                    } 
                end
                
                roles = ret[cluster]['roles']
                
                if not roles.has_key? role
                    roles[role] = {
                        'client' => [],
                        'present' => true,
                    }
                end
                roles[role]['client'] << {
                    'max_connections' => info['max_connections'],
                    'host' => info['client_host'],
                }
            end
            
            ret
        rescue => e
            {}
            #e
        end
    end 
end
