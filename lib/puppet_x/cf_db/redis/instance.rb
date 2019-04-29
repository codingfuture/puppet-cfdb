#
# Copyright 2019 (c) Andrey Galkin
#


module PuppetX::CfDb::Redis::Instance
    include PuppetX::CfDb::Redis
    
    def create_redis(conf)
        debug('create_redis')

        cf_system = self.cf_system()
        
        root_dir = conf[:root_dir]
        conf_dir = "#{root_dir}/conf"
        data_dir = "#{root_dir}/data"
        tmp_dir = "#{root_dir}/tmp"
        backup_dir = conf[:backup_dir]
        backup_wal_dir = "#{backup_dir}/log"
        
        cluster = conf[:cluster]
        service_name = conf[:service_name]
        repmgr_service_name = "#{service_name}-redis"
        is_secondary = conf[:is_secondary]
        is_cluster = conf[:is_cluster]
        is_arbitrator = conf[:is_arbitrator]
        cluster_addr = conf[:cluster_addr]
        access_list = conf[:access_list]
        type = conf[:type]
        conf_file = "#{conf_dir}/redis.conf"
        conf_orig_file = "#{conf_dir}/redis.conf.orig"
        sentinel_file = "#{conf_dir}/sentinel.conf"
        sentinel_orig_file = "#{conf_dir}/sentinel.conf.orig"
        
        run_dir = "/run/#{service_name}"
        restart_required_file = "#{conf_dir}/restart_required"

        user = conf[:user]
        settings_tune = conf[:settings_tune]
        is_bootstrap = conf[:is_bootstrap]
        cfdb_settings = settings_tune.fetch('cfdb', {})
        redis_tune = settings_tune.fetch('redis', {})
        sentinel_tune = settings_tune.fetch('sentinel', {})
        fqdn = Facter['fqdn'].value()

        root_pass = cfdb_settings['shared_secret']
        
        if root_pass.nil? or root_pass.empty?
            fail("Shared secret must be generated in DSL")
        end

        #---
        if is_bootstrap
            warning("Please note that is_bootstrap MUST BE set false during normal operation")
        end

        # calculate based on user access list x limit
        #---
        max_connections = 10
        have_external_conn = false
        
        access_list.each do |role_id, rinfo|
            rinfo.each do |v|
                host = v['host']
                max_conn = v['maxconn']
                max_connections += max_conn
                client_host = v['client_host']
                
                if host != fqdn or (client_host != 'localhost' and client_host != '127.0.0.1' and client_host != fqdn)
                    have_external_conn = true
                end
            end
        end
        
        max_connections_roundto = cfdb_settings.fetch('max_connections_roundto', 100).to_i
        max_connections = round_to(max_connections_roundto, max_connections)

        #---
        if have_external_conn or is_cluster
            bind_address = cfdb_settings['listen'] || cfdb_settings['cluster_listen'] || '0.0.0.0'
            cluster_bind_address = cfdb_settings['cluster_listen'] || '0.0.0.0'
        else
            bind_address = '127.0.0.1'
            cluster_bind_address = bind_address
        end
        #---
        
        port = cfdb_settings['port']
        fail('Missing port') if port.nil?

        sentinel_port = port + SENTINEL_OFFSET
        sock_file = "#{run_dir}/service.sock"

        #---
        redisenv = [
            "DB_HOST=#{bind_address}",
            "DB_PORT=#{port}",
            "SENTINEL_PORT=#{sentinel_port}",
            "ROOT_PASS=#{root_pass}",
        ]
        cf_system.atomicWrite("#{root_dir}/.redisrc.sh", redisenv, {:user => user, :show_diff => false})

        #---
        avail_mem = get_memory(cluster)
        left_mem = avail_mem * 1024
        backlog_mem = 0

        if is_cluster and !is_arbitrator
            left_mem -= (cfdb_settings.fetch('sentinel_mem', 8).to_f * 1024).to_i

            backlog_coef = cfdb_settings.fetch('backlog_percent', 1).to_f / 100.0
            backlog_mem = (left_mem * backlog_coef).to_i
            left_mem -= backlog_mem
        end

        data_coef = cfdb_settings.fetch('data_percent', 70).to_f / 100.0
        data_mem = (left_mem * data_coef).to_i
        left_mem -= data_mem
        
        #==================================================
        primary_node = "#{cluster_bind_address} #{port}"
        
        if is_secondary or is_arbitrator
            for v in cluster_addr
                next if v['is_arbitrator'] || v['is_secondary']
                primary_node = "#{v['addr']} #{v['port']}"
            end
        end

        slice_name = "system-cfdb_#{cluster}"
        create_slice(slice_name, conf)

        if !is_arbitrator
            # defaults
            conf_settings = {
                'unixsocketperm' => '0777',
                'tcp-backlog' => max_connections,
                'timeout' => 0,
                'tcp-keepalive' => 10,
                'loglevel' => 'notice',
                'databases' => 1,
                'save' => '600 10000',
                'stop-writes-on-bgsave-error' => 'no',
                'rdbcompression' => 'yes',
                'rdbchecksum' => 'yes',
                'slave-serve-stale-data' => 'no',
                'slave-read-only' => 'yes',
                'repl-diskless-sync' => 'yes',
                'repl-diskless-sync-delay' => 0,
                'repl-ping-slave-period' => 5,
                'repl-timeout' => 15,
                'repl-disable-tcp-nodelay' => 'no',
                'repl-backlog-size' => "#{backlog_mem}kb",
                'repl-backlog-ttl' => 0,
                'slave-priority' => 100,
                'min-slaves-to-write' => 0,
                'min-slaves-max-lag' => 10,
                'maxmemory-policy' => 'noeviction',
                'maxmemory-samples' => 5,
                'lazyfree-lazy-eviction' => 'no',
                'lazyfree-lazy-expire' => 'yes',
                'lazyfree-lazy-server-del' => 'no',
                'slave-lazy-flush' => 'yes',

                'appendfsync' => 'everysec',
                'auto-aof-rewrite-percentage' => 100,
                'auto-aof-rewrite-min-size' => "#{data_mem}kb",
                'aof-load-truncated' => 'yes',
                'aof-use-rdb-preamble' => 'yes',
                'aof-rewrite-incremental-fsync' => 'yes',

                'lua-time-limit' => 5000,
                'slowlog-log-slower-than' => 10000,
                'slowlog-max-len' => 128,
                'latency-monitor-threshold' => 0,
                'notify-keyspace-events' => '""',

                'hash-max-ziplist-entries' => 512,
                'hash-max-ziplist-value' => 64,
                'list-max-ziplist-size' => -2,
                'list-compress-depth' => 0,
                'set-max-intset-entries' => 512,
                'zset-max-ziplist-entries' => 128,
                'zset-max-ziplist-value' => 64,
                'hll-sparse-max-bytes' => 3000,
                'activerehashing' => 'yes',
                'hz' => 10,

                'client-output-buffer-limit normal' => '0 0 0',
                'client-output-buffer-limit slave' => '256mb 64mb 60',
                'client-output-buffer-limit pubsub' => '32mb 8mb 60',
            }

            # forced
            forced_settings = {
                'bind' => (bind_address != cluster_bind_address) ?
                            "#{bind_address} #{cluster_bind_address}" :
                            "#{bind_address}",
                'port' => port,
                'unixsocket' => sock_file,
                'protected-mode' => (have_external_conn or is_cluster) ? 'yes' : 'no',
                'daemonize' => 'no',
                'supervised' => 'systemd',
                'syslog-enabled' => 'yes',
                'syslog-ident' => service_name,
                'dbfilename' => 'dump.rds',
                'dir' => data_dir,
                'masterauth' => root_pass,
                'requirepass' => root_pass,
                'maxclients' => max_connections,
                'maxmemory' => "#{data_mem}kb",

                'appendonly' => 'yes',
                'appendfilename' => 'log.aof',
                'cluster-enabled' => 'no',
            }

            if is_cluster and !is_bootstrap and cluster_addr.size > 0
                if is_secondary
                    forced_settings['slaveof'] = primary_node
                else
                    # Just prevent starting as master
                    cluster_addr.each { |v|
                        next if v['is_arbitrator']
                        forced_settings['slaveof'] = "#{v['addr']} #{v['port']}"
                    }
                end
            end
            
            conf_settings.merge! redis_tune
            conf_settings.merge! forced_settings

            config_file_changed = cf_system.atomicWrite(conf_orig_file, redis_conf(conf_settings), { :user => user })

            # Prepare service file
            #---
            service_ini = {
                '# Package Version' => PuppetX::CfSystem::Util.get_package_version(
                                            "redis-server"),
                'LimitNOFILE' => 'infinity',
                'LimitNPROC' => 'infinity',
                'LimitAS' => 'infinity',
                'LimitFSIZE' => 'infinity',
                'TimeoutStopSec' => 0,
                'KillSignal' => 'SIGTERM',
                'KillMode' => 'process',
                'SendSIGKILL' => 'no',
                'ExecStartPre' => "/bin/cp -f #{conf_orig_file} #{conf_file}",
                'ExecStart' => "#{REDIS_SERVER} #{conf_file}",
                'ExecStartPost' => "/bin/rm -f #{restart_required_file}",
                'OOMScoreAdjust' => -200,
            }
            service_env = {}
            service_changed = create_service(conf, service_ini, service_env, slice_name)
            
            config_changed = config_file_changed || service_changed

            if !File.exists?(data_dir)
                FileUtils.mkdir(data_dir, :mode => 0750)
                FileUtils.chown(user, user, data_dir)
            elsif config_changed
                FileUtils.touch(restart_required_file)
                FileUtils.chown(user, user, restart_required_file)
            end

            if File.exists?(restart_required_file)
                warning("#{user} configuration update. Service restart is required!")
                warning("Please run when safe: #{PuppetX::CfSystem::SYSTEMD_CTL} restart #{service_name}.service")
            end

            systemctl('enable', "#{service_name}.service")
            systemctl('start', "#{service_name}.service")
        end

        #==================================================
        if is_cluster
            # defaults
            conf_sentinel = {
                'sentinel monitor' => '', # just for config order
                'sentinel down-after-milliseconds' => "#{cluster} 1000",
                'sentinel failover-timeout' => "#{cluster} 3000",
                'sentinel parallel-syncs' => "#{cluster} #{cluster_addr.size}",
            }

            # forced
            quorum = [((cluster_addr.size + 1) / 2.0).ceil, 1].max

            forced_sentinel = {
                'bind' => "#{cluster_bind_address}",
                'port' => sentinel_port,
                'dir' => root_dir,
                'sentinel monitor' => "#{cluster} #{primary_node} #{quorum}",
                'sentinel auth-pass' => "#{cluster} #{root_pass}",
            }
            
            conf_sentinel.merge! sentinel_tune
            conf_sentinel.merge! forced_sentinel

            conf_changed = cf_system.atomicWrite(sentinel_orig_file, redis_conf(conf_sentinel),
                                                 { :user => user })

            # Prepare service file
            #---
            if is_arbitrator
                sentinel_service_name = service_name

                # Just make the default checks happy
                if !File.exists?(data_dir)
                    FileUtils.mkdir(data_dir, :mode => 0750)
                    FileUtils.chown(user, user, data_dir)
                end
            else
                sentinel_service_name = "#{service_name}-arb"
            end

            service_ini = {
                '# Package Version' => PuppetX::CfSystem::Util.get_package_version(
                                            "redis-sentinel"),
                'LimitNOFILE' => 'infinity',
                'LimitNPROC' => 'infinity',
                'LimitAS' => 'infinity',
                'LimitFSIZE' => 'infinity',
                'TimeoutStopSec' => 0,
                'KillSignal' => 'SIGTERM',
                'KillMode' => 'process',
                'SendSIGKILL' => 'no',
                'ExecStart' => "#{REDIS_SENTINEL} #{sentinel_file}",
            }
            service_env = {}
            service_changed = create_service(conf, service_ini, service_env,
                                             slice_name, sentinel_service_name)

            if conf_changed
                warning("> reconfiguring #{sentinel_service_name} from scratch")
                systemctl('stop', "#{sentinel_service_name}.service")
                cf_system.atomicWrite(sentinel_file, redis_conf(conf_sentinel), { :user => user })
                systemctl('start', "#{sentinel_service_name}.service")
            elsif service_changed
                systemctl('restart', "#{sentinel_service_name}.service")
            end

            systemctl('enable', "#{sentinel_service_name}.service")
            systemctl('start', "#{sentinel_service_name}.service")
        end

        #==================================================

        # Check cluster is complete
        #---
        check_cluster_redis(conf)
    end
    
    def check_cluster_redis(conf)
        return true if !conf[:is_cluster]
        return true if conf[:is_arbitrator]

        res = sudo('-u', conf[:user],
                   "#{conf[:root_dir]}/../bin/cfdb_#{conf[:cluster]}_rediscli",
                   '--raw', 'info', 'replication')
        info = {}
        res.strip().split("\n").each { |l|
            l = l.split(':', 2)
            next if l.length != 2
            info[l[0]] = l[1].strip()
        }

        if conf[:is_secondary]
            if info['role'] != 'slave'
                warning("! #{conf[:service_name]} is not an active slave (#{info['role']}) !")
            end
        else
            if info['role'] != 'master'
                warning(" ! #{conf[:service_name]} is not an active master (#{info['role']}) !")
            else
                slaves = 0

                conf[:cluster_addr].each { |v|
                    slaves += 1 if !v['is_arbitrator']
                }

                if slaves != info['connected_slaves'].to_i
                    warning("! Unexpected numer of slaves #{slaves} vs #{info['connected_slaves']} for #{conf[:service_name]} !")
                end
            end
        end

        true
    end

    def redis_conf(settings)
        settings.map { |k, v|
            "#{k} #{v}"
        }
    end
end
