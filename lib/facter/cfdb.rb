require 'json'

# Done this way due to some weird behavior in tests also ignoring $LOAD_PATH
begin
    require File.expand_path( '../../puppet_x/cf_system/provider_base', __FILE__ )
rescue LoadError
    require File.expand_path( '../../../../cfsystem/lib/puppet_x/cf_system/provider_base', __FILE__ )
end

Facter.add('cfdb') do
    setcode do
        cfsystem_json = PuppetX::CfSystem::CFSYSTEM_CONFIG
        begin
            json = File.read(cfsystem_json)
            json = JSON.parse(json)
            sections = json['sections']
            persistent = json['persistent']['ports']
            
            ret = {}
            roles = {}
            
            sections['cf10db3_role'].each do |k, info|
                cluster = info['cluster']
                user = info['user']
                roles[cluster] = {} if not roles.has_key? cluster
                roles[cluster][user] = {
                    'database' => info['database'],
                    'password' => info['password'],
                    'present' => true,
                }
            end
            
            sections['cf10db1_instance'].each do |k, info|
                cluster = info['cluster']
                ret[cluster] = {
                    'type' => info['type'],
                    'roles' => roles[cluster],
                    'socket' => "/run/#{info['service_name']}/service.sock",
                    'host' => info['settings_tune'].fetch('cfdb', {}).fetch('listen', nil),
                    'port' => persistent[cluster],
                    'is_secondary' => info['is_secondary'],
                    'is_cluster' => info['is_cluster'],
                    'present' => true,
                }
            end
            
            ret
        rescue => e
            {}
            #e
        end
    end 
end
