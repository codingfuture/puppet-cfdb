#
# Copyright 2016-2019 (c) Andrey Galkin
#


require File.expand_path( '../../../../puppet_x/cf_db', __FILE__ )

Puppet::Type.type(:cfdb_haproxy).provide(
    :cfdb,
    :parent => PuppetX::CfDb::ProviderBase
) do
    desc "Provider for cfdb_haproxy"
    
    commands :systemctl => PuppetX::CfSystem::SYSTEMD_CTL
    HAPROXY_SYSTEMD = '/usr/sbin/haproxy-systemd-wrapper' unless defined? HAPROXY_SYSTEMD
    HAPROXY = '/usr/sbin/haproxy' unless defined? HAPROXY
    
    def self.get_config_index
        'cf20db1_haproxy'
    end

    def self.get_generator_version
        cf_system().makeVersion(__FILE__)
    end
    
    def self.check_exists(params)
        debug('check_exists')
        begin
            systemctl(['status', "#{params[:service_name]}.service"])
        rescue => e
            warning(e)
            #warning(e.backtrace)
            false
        end
    end

    def self.on_config_change(newconf)
        newconf = newconf[newconf.keys[0]]
        cf_system = self.cf_system()
        
        root_dir = newconf[:root_dir]
        bin_dir = "#{root_dir}/bin"
        conf_dir = "#{root_dir}/conf"
        conf_file = "#{conf_dir}/haproxy.conf"
        pki_dir = "#{root_dir}/pki"
        puppet_pki_dir = "#{pki_dir}/puppet"

        
        service_name = newconf[:service_name]
        run_dir = "/run/#{service_name}"
        user = service_name
        settings_tune = newconf[:settings_tune]
        cfdb_settings = settings_tune.fetch('cfdb', {})
        
        frontend_index = Puppet::Type.type(:cfdb_haproxy_frontend).provider(:cfdb).get_config_index
        frontends = cf_system().config.get_new(frontend_index) || {}
        endpoint_index = Puppet::Type.type(:cfdb_haproxy_endpoint).provider(:cfdb).get_config_index
        endpoints = cf_system().config.get_new(endpoint_index) || {}

        inter = cfdb_settings.fetch('inter', '3s')
        fastinter = cfdb_settings.fetch('fastinter', '500ms')

        open_files = 100
        
        # Prepare server PKI
        #---
        # NOTE: even though HAProxy support directory in crt paramter, it's not too safe
        local_pem = [
            File.read("#{puppet_pki_dir}/local.crt"),
            File.read("#{puppet_pki_dir}/local.key"),
            File.read("#{pki_dir}/dh.pem"),
        ].join
        cert_file = "#{pki_dir}/haproxy.pem"
        cf_system.atomicWrite(cert_file, local_pem, {:user => user, :show_diff => false})
        
        # HAProxy config
        #==================================================
        conf = {
            'global' => {
                'log' => '/dev/log local0',
                'daemon' => '',
                'external-check' => '',
                'group' => user,
                'user' => user,
                'stats socket'  => "#{run_dir}/stats.sock mode 660 level admin group #{user}",
                'ssl-server-verify' => 'required',
                'ssl-default-server-options' => [
                    # not working here
                    #"ca-file #{puppet_pki_dir}/ca.crt",
                    #"crl-file #{puppet_pki_dir}/crl.crt",
                    'no-sslv3',
                    #'verify required',
                ].join(' '),
                'spread-checks' => 5,
                'tune.ssl.default-dh-param' => 2048,
                "# unfortunately, haproxy misbehaves with external-check & epoll :(" => '',
                "# reported as issue about CLOEXEC with patch provided" => '',
                'noepoll' => '',
                '# as we work with unix sockets, there is no point in splice() :(' => '',
                'nosplice' => '',
            },
            'defaults' => {
                #'log global' => '',
                'timeout connect' => '5s',
                'timeout client' => '10m',
                'timeout server' => '10m',
                'timeout check' => fastinter,
                'option abortonclose' => '',
                'option dontlog-normal' => '',
                'option dontlognull' => '',
                # this causes async RST issues
                #'option nolinger' => '',
                #'option splice-auto' => '',
                #'option splice-request' => '',
                #'option splice-response' => '',
                'option srvtcpka' => '',
                'option clitcpka' => '',
            },
        }
            
        conf_listeners = {}
        conf_backends = {}
        conf_frontends = {}
        
        # Connections to DB servers
        #---
        frontends.each do |title, finfo|
            type = finfo[:type]
            cluster = finfo[:cluster]
            socket = finfo[:socket]
            access_user = finfo[:access_user]
            max_connections = finfo[:max_connections]
            is_secure = finfo[:is_secure]
            distribute_load = finfo[:distribute_load]
            cluster_addr = finfo[:cluster_addr]
            
            use_unix_socket = finfo[:use_unix_socket]
            local_host = finfo[:local_host]
            local_port = finfo[:local_port]
                       
            backend_name = "#{type}:#{cluster}"
            backend_name += ":lb" if distribute_load
            backend_name += ":secure" if is_secure

            backend_conf_index = "backend #{backend_name}"
                       
            if conf_backends.has_key? backend_conf_index
                backend_conf = conf_backends[backend_conf_index]
            else
                if type == 'elasticsearch'
                    backend_conf = {
                        'mode' => 'http',
                        'retries' => 1,
                        'balance' => 'leastconn',
                        'option httpchk' => 'GET /_cluster/health?local HTTP/1.0',
                        'http-check expect' => '! string "status":"red"',
                    }
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
                
                    backend_conf['external-check command'] = "#{bin_dir}/check_#{cluster}"
                end

                conf_backends[backend_conf_index] = backend_conf
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
                host = sinfo['host']
                ip = sinfo['addr']
                port = sinfo['port']
                server_id = sinfo['server']
                
                begin
                    ip = IPAddr.new(ip)
                    
                    if ip.ipv6?
                        ip = "[#{ip}]"
                    end
                rescue
                end

                host_use_unix_socket = (host == Puppet[:certname])

                if type === 'elasticsearch'
                    host_use_unix_socket = false
                end

                if host_use_unix_socket
                    server_dst = "unix@/run/cf#{type}-#{cluster}/"

                    if type == 'postgresql'
                        server_dst += ".s.PGSQL.#{port}"
                    elsif type == 'mongodb'
                        server_dst += "mongodb-#{port}.sock"
                    else
                        server_dst += 'service.sock'
                    end
                else
                    server_dst = "#{ip}:#{port}"
                end
                
                secure_server = sinfo['secure']

                server_config = ["#{server_dst} check fall 2 rise 1 inter #{inter} fastinter #{fastinter}"]
                
                if secure_server
                    server_config << 'weight 10'
                    server_config << 'ssl'
                    server_config << "ca-file #{puppet_pki_dir}/ca.crt"
                    server_config << "crl-file #{puppet_pki_dir}/crl.crt"
                    server_config << "crt #{cert_file}"
                    server_config << 'no-sslv3'
                    server_config << 'verify required'
                    server_config << "verifyhost #{host}"
                else
                    server_config << 'weight 100'
                end
                
                if !distribute_load
                    server_config << "on-marked-down shutdown-sessions"

                    if sinfo['backup']
                        server_config << "backup"
                    else
                        # This is primarily needed for MongoDB, Redis and other assymetric clusters
                        server_config << "on-marked-up shutdown-backup-sessions"
                    end
                end
                
                server_config << sinfo['extra'] if sinfo.has_key? 'extra'
                backend_conf["server #{server_id}"] = server_config.join(' ')
                
                # Configure block for checks
                #---
                check_listen = "listen #{server_id}:check"
                conn_per_check = 2
                
                if type === 'elasticsearch'
                    # noop
                elsif conf_listeners.has_key? check_listen
                    conf_listeners[check_listen]['maxconn'] += conn_per_check
                else
                    check_server_config = ["#{server_dst}"]

                    if secure_server
                        check_server_config << 'ssl'
                        check_server_config << "ca-file #{puppet_pki_dir}/ca.crt"
                        check_server_config << "crl-file #{puppet_pki_dir}/crl.crt"
                        check_server_config << "crt #{cert_file}"
                        check_server_config << 'no-sslv3'
                        check_server_config << 'verify required'
                        check_server_config << "verifyhost #{host}"
                    end

                    conf_listeners[check_listen] = {
                        'mode' => 'tcp',
                        #'option tcplog' => '',
                        #'log global' => '',
                        'retries' => 0,
                        'maxconn' => conn_per_check,
                        'bind' => "unix@/run/#{service_name}/check__#{server_id}.sock user #{user} group #{user} mode 660",
                        "server check__#{server_id}" => check_server_config.join(' ')
                    }
                end
                
                open_files += conn_per_check * 2
            end
            
                        
            if use_unix_socket
                bind = "unix@#{socket} user #{access_user} group #{access_user} mode 660"
            else
                bind = "#{local_host}:#{local_port}"
            end

                       
            conf_frontends["frontend #{title}"] = {
                'mode' => 'tcp',
                #'option tcplog' => '',
                #'log global' => '',
                'bind' => bind,
                'backlog' => cf_system.fitRange(max_connections, 4096, max_connections),
                'maxconn' => max_connections,
                'default_backend' => backend_name,
            }
                       
            open_files += max_connections * 2
        end
        
        # Endpoints for secure connections
        #---
        endpoints.each do |title, finfo|
            type = finfo[:type]
            cluster = finfo[:cluster]
            cluster_service_name = finfo[:service_name]
            listen = finfo[:listen]
            sec_port = finfo[:sec_port]
            max_connections = finfo[:max_connections]
                       
            endpoint_name = "listen #{type}:#{cluster}:secure_endpoint"
            
            if conf_listeners.has_key? endpoint_name
                endpoint_conf = conf_listeners[endpoint_name]
            else
                socket = "unix@/run/#{cluster_service_name}/"
                sock_type = 'unix'
                
                if type === 'elasticsearch'
                    server_port = (sec_port - PuppetX::CfDb::SECURE_PORT_OFFSET)
                    socket = "#{listen}:#{server_port}"
                    sock_type = 'tcp'
                elsif type == 'postgresql'
                    server_port = (sec_port - PuppetX::CfDb::SECURE_PORT_OFFSET)
                    socket += ".s.PGSQL.#{server_port}"
                elsif type == 'mongodb'
                    server_port = (sec_port - PuppetX::CfDb::SECURE_PORT_OFFSET)
                    socket += "mongodb-#{server_port}.sock"
                else
                    socket += 'service.sock'
                end
                
                bind_config = ["#{listen}:#{sec_port}"]
                bind_config << 'ssl'
                bind_config << "ca-file #{puppet_pki_dir}/ca.crt"
                bind_config << "crl-file #{puppet_pki_dir}/crl.crt"
                bind_config << "crt #{cert_file}"
                bind_config << 'no-sslv3'
                bind_config << 'verify required'

                endpoint_conf = {
                    'mode' => 'tcp',
                    'retries' => 0,
                    'maxconn' => 0,
                    'bind' => bind_config.join(' '),
                    'server' => "#{type}_#{cluster}_#{sock_type} #{socket}",
                }

                conf_listeners[endpoint_name] = endpoint_conf
            end
            
            endpoint_conf['maxconn'] += max_connections
            endpoint_conf['backlog'] = cf_system.fitRange(endpoint_conf['maxconn'], 4096, endpoint_conf['maxconn'])
            
            
            open_files += max_connections * 2
        end
        
        #---
        conf['global']['maxconn'] = open_files
        
        # stable sort of content
        #---
        [conf_listeners, conf_backends, conf_frontends].each do |subconf|
            subconf.keys.sort.each do |k|
                conf[k] = subconf[k]
            end
        end
        
        
        #---
        settings_tune.each do |k, v|
            next if k == 'cfdb'

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
                'ExecReload' => '/bin/kill -USR2 $MAINPID',
                'WorkingDirectory' => root_dir,
            },
        }

        if File.exists? HAPROXY_SYSTEMD
            content_ini['Service'].merge!({
                'ExecStart' => "#{HAPROXY_SYSTEMD} -f #{conf_file} -p #{run_dir}/haproxy.pid",
            })
        else
            content_ini['Service'].merge!({
                'ExecStart' => "#{HAPROXY} -Ws -f #{conf_file} -p #{run_dir}/haproxy.pid",
            })
        end
        
        service_changed = self.cf_system().createService({
            :service_name => service_name,
            :user => 'root',
            :content_ini => content_ini,
            :cpu_weight => newconf[:cpu_weight],
            :io_weight => newconf[:io_weight],
            :mem_limit => cf_system.getMemory(service_name),
            :mem_lock => true,
        })
        
        if service_changed
            systemctl('start', "#{service_name}.service")
        end
        #==================================================
        
        if config_changed or service_changed
            warning(">> reloading #{service_name}")
            systemctl('reload-or-restart', "#{service_name}.service")
        end
    end
end
