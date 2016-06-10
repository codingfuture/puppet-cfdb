
require File.expand_path( '../../../../puppet_x/cf_db', __FILE__ )

Puppet::Type.type(:cfdb_haproxy).provide(
    :cfdb,
    :parent => PuppetX::CfDb::ProviderBase
) do
    desc "Provider for cfdb_haproxy"
    
    commands :systemctl => '/bin/systemctl'
    HAPROXY_SYSTEMD = '/usr/sbin/haproxy-systemd-wrapper' unless defined? HAPROXY_SYSTEMD
    
    def self.get_config_index
        'cf20db1_haproxy'
    end

    def self.get_generator_version
        cf_system().makeVersion(__FILE__)
    end

    def self.on_config_change(newconf)
        newconf = newconf[newconf.keys[0]]
        cf_system = self.cf_system()
        
        root_dir = newconf[:root_dir]
        bin_dir = "#{root_dir}/bin"
        conf_dir = "#{root_dir}/conf"
        conf_file = "#{conf_dir}/haproxy.conf"
        ssl_dir = "#{root_dir}/pki/puppet"
        
        service_name = newconf[:service_name]
        run_dir = "/run/#{service_name}"
        user = service_name
        settings_tune = newconf[:settings_tune]
        
        frontend_index = Puppet::Type.type(:cfdb_haproxy_frontend).provider(:cfdb).get_config_index
        frontends = cf_system().config.get_new(frontend_index)
        backends = {}

        open_files = 100
        # HAProxy config
        #==================================================
        conf = {
            'global' => {
                'log' => '/dev/log local0',
                'daemon' => '',
                'external-check' => '',
                'group' => user,
                'user' => user,
                'stats socket'  => "#{run_dir}/stats.sock mode 660 level admin",
                'ssl-server-verify' => 'required',
                'ssl-default-server-options' => [
                    # not working here
                    #"ca-file #{ssl_dir}/ca.crt",
                    #"crl-file #{ssl_dir}/crl.crt",
                    'no-sslv3',
                    #'verify required',
                ].join(' '),
            },
            'defaults' => {
                'timeout connect' => '5s',
                'timeout client' => '10m',
                'timeout server' => '10m',
                'option abortonclose' => '',
                'option dontlog-normal' => '',
                'option dontlognull' => '',
                'option nolinger' => '',
                'option splice-auto' => '',
                'option splice-request' => '',
                'option splice-response' => '',
                'option srvtcpka' => '',
            },
        }
        
        #---
        frontends.each do |title, finfo|
            type = finfo[:type]
            cluster = finfo[:cluster]
            socket = finfo[:socket]
            role = finfo[:role]
            access_user = finfo[:access_user]
            max_connections = finfo[:max_connections]
            is_secure = finfo[:is_secure]
            distribute_load = finfo[:distribute_load]
            cluster_addr = finfo[:cluster_addr]
                       
            backend_name = "#{type}:#{cluster}"
            backend_name += ":lb" if distribute_load
            backend_name += ":secure" if is_secure
                       
                       
            if conf.has_key? "backend #{backend_name}"
                backend_conf = conf["backend #{backend_name}"]
            else
                backend_conf = {
                    'mode' => 'tcp',
                    'option external-check' => '',
                    'retries' => 1,
                }
                
                if distribute_load
                    backend_conf['balance'] = 'leastconn'
                else
                    backend_conf['balance'] = 'first'
                end
                
                case type
                when 'postgresql' then
                    backend_conf['option pgsql-check'] = role
                when 'redis' then
                    backend_conf['option redis-check'] = ''
                else
                    backend_conf['external-check command'] = "#{bin_dir}/check_#{cluster}_#{role}"
                end

                conf["backend #{backend_name}"] = backend_conf
            end
            
            # do not sort in place
            cluster_addr = cluster_addr.sort do |a, b|
                # first sort based on backup property
                if a['backup'] && !b['backup']
                    1
                elsif !a['backup'] && b['backup']
                    -1
                # then sort based on secure property
                elsif a['secure'] && !b['secure']
                    1
                elsif !a['secure'] && b['secure']
                    -1
                # finally, sort based on server name
                else
                    a['server'] <=> b['server']
                end
            end
            
            # normally, each "cluster_addr" parameter must be identical per cluster
            # so, the items will get overrided in place
            cluster_addr.each do |sinfo|
                ip = sinfo['addr']
                port = sinfo['port']
                
                begin
                    ip = IPAddr.new(ip)
                    
                    if ip.ipv6?
                        ip = "[#{ip}]"
                    end
                rescue
                end
                
                secure_server = (is_secure or sinfo['secure'])
                port += PuppetX::CfDb::SECURE_PORT_OFFSET if secure_server

                server_config = ["#{ip}:#{port} check fall 2 rise 1 fastinter 500ms"]
                
                if secure_server
                    server_config << 'weight 10'
                    server_config << 'ssl'
                    server_config << "ca-file #{ssl_dir}/ca.crt"
                    server_config << "crl-file #{ssl_dir}/crl.crt"
                    server_config << 'no-sslv3'
                    server_config << 'verify required'
                    server_config << "verifyhost #{ip}"
                else
                    server_config << 'weight 100'
                end
                
                if !distribute_load and sinfo['backup']
                    server_config << "backup"
                end
                
                server_config << sinfo['extra'] if sinfo.has_key? 'extra'
                backend_conf["server #{sinfo['server']}"] = server_config.join(' ')
            end
                       
            conf["frontend #{title}"] = {
                'mode' => 'tcp',
                'option tcplog' => '',
                'log global' => '',
                'bind' => "unix@#{socket} user #{access_user} group #{access_user} mode 660",
                'backlog' => cf_system.fitRange(max_connections, 4096, max_connections),
                'maxconn' => max_connections,
                'default_backend' => backend_name,
            }
                       
            open_files += max_connections * 2
        end
        
        
        #---
        settings_tune.each do |k, v|
            if v.nil?
                conf.delete k if conf.has_key? k
            else
                if conf.has_key? k
                    conf[k].merge! v
                else
                    conf[k] = v.clone
                end
            end
        end
        #==================================================
        conf = conf.map do |k, v|
            "\n#{k}\n" + v.map{ |ki, vi|
                "    #{ki} #{vi}" unless vi.nil?
            }.join("\n")
        end
        conf << ""
        
        config_changed = cf_system.atomicWrite(conf_file, conf, {:user => user})
        
        # Service File
        #==================================================
        content_ini = {
            'Unit' => {
                'Description' => "CFDB HAProxy",
            },
            'Service' => {
                'LimitNOFILE' => cf_system.fitRange(64*1024, open_files),
                'ExecStart' => "#{HAPROXY_SYSTEMD} -f #{conf_file} -p #{run_dir}/cfhaproxy.pid",
                'ExecReload' => '/bin/kill -USR2 $MAINPID',
                'WorkingDirectory' => root_dir,
            },
        }
        
        service_changed = self.cf_system().createService({
            :service_name => service_name,
            :user => 'root',
            :content_ini => content_ini,
            :cpu_weight => newconf[:cpu_weight],
            :io_weight => newconf[:io_weight],
            :mem_limit => mem_limit = cf_system.getMemory(service_name),
            :mem_lock => true,
        })
        
        if service_changed
            systemctl('start', "#{service_name}.service")
        end
        #==================================================
        
        if config_changed or service_changed
            warning(">> reloading #{service_name}")
            systemctl('reload', "#{service_name}.service")
        end
    end
end
