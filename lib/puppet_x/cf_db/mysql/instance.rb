#
# Copyright 2016-2017 (c) Andrey Galkin
#


module PuppetX::CfDb::MySQL::Instance
    include PuppetX::CfDb::MySQL
    
    def create_mysql(conf)
        debug('create_mysql')
        cf_system = self.cf_system()
        
        root_dir = conf[:root_dir]
        conf_dir = "#{root_dir}/conf"
        data_dir = "#{root_dir}/data"
        tmp_dir = "#{root_dir}/tmp"
        pki_dir = "#{root_dir}/pki/puppet"
        
        cluster = conf[:cluster]
        service_name = conf[:service_name]
        version = conf[:version]
        is_secondary = conf[:is_secondary]
        is_cluster = conf[:is_cluster]
        is_arbitrator = conf[:is_arbitrator]
        cluster_addr = conf[:cluster_addr]
        access_list = conf[:access_list]
        server_id = 1 # TODO
        type = conf[:type]
        conf_file = "#{conf_dir}/mysql.cnf"
        garbd_conf_file = "#{conf_dir}/garbd.config"
        client_conf_file = "#{root_dir}/.my.cnf"
        init_file = "#{conf_dir}/setup.sql"
        
        run_dir = "/run/#{service_name}"
        sock_file = "#{run_dir}/service.sock"
        pid_file = "#{run_dir}/service.pid"
        restart_required_file = "#{conf_dir}/restart_required"
        upgrade_file = "#{conf_dir}/upgrade_stamp"

        user = conf[:user]
        settings_tune = conf[:settings_tune]
        is_bootstrap = conf[:is_bootstrap]
        cfdb_settings = settings_tune.fetch('cfdb', {})
        mysqld_tune = settings_tune.fetch('mysqld', {})
        
        if is_secondary
            root_pass = cfdb_settings['shared_secret']
            
            if root_pass.nil? or root_pass.empty?
                fail("Secondary instance must get non-empty shared_secret.\n" +
                     "Something is wrong with facts.\n" +
                     "Please try to reprovision primary instance first.")
            end
            
            cf_system.genSecret("cfdb/#{cluster}", -1, root_pass)
        else
            root_pass = cf_system.genSecret("cfdb/#{cluster}", ROOT_PASS_LEN)
        end
        
        data_exists = File.exists?(data_dir)
        
        if cfdb_settings.has_key? 'optimize_ssd'
            optimize_ssd = cfdb_settings['optimize_ssd']
        else
            optimize_ssd = !is_low_iops(root_dir)
        end
        
        secure_cluster = cfdb_settings.fetch('secure_cluster', false)
        init_db_from = cfdb_settings.fetch('init_db_from', nil)
        
        fqdn = Facter['fqdn'].value()
        
        #---
        ver_parts = version.split('.')
        is_56 = (ver_parts[0] == '5' and ver_parts[1] == '6')
        is_57 = (ver_parts[0] == '5' and ver_parts[1] == '7')
        
        if !is_56 and !is_57
            fail('At the moment, only MySQL v5.6 and v5.7 are supported')
        end
        
        if is_arbitrator
            upgrade_ver = 'NONE'
        else
            if is_57
                upgrade_ver = sudo('-H', '-u', user, MYSQL_UPGRADE, '--version')
            else
                upgrade_ver = sudo('-H', '-u', user, MYSQL_UPGRADE, '--help').split("\n")[0]
            end
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
                
                if host != fqdn
                    have_external_conn = true
                end
            end
        end
        
        max_connections_roundto = cfdb_settings.fetch('max_connections_roundto', 100).to_i
        max_connections = round_to(max_connections_roundto, max_connections)
        #---
        
        #---
        if have_external_conn or is_cluster
            bind_address = cfdb_settings.fetch('listen', '0.0.0.0')
        else
            bind_address = '127.0.0.1'
        end
        
        port = cf_system.genPort(cluster, cfdb_settings.fetch('port', nil))
        
        if is_cluster
            galera_port = port + GALERA_PORT_OFFSET
            sst_port = port + SST_PORT_OFFSET
            ist_port = port + IST_PORT_OFFSET
            cf_system.genPort(cluster + "#galera", galera_port)
            cf_system.genPort(cluster + "#sst", sst_port)
            cf_system.genPort(cluster + "#ist", ist_port)
        end
        #---

        # Auto-tune to have enough open table cache        
        #---
        inodes_min = cfdb_settings.fetch('inodes_min', 1000).to_i
        inodex_max = cfdb_settings.fetch('inodex_max', 10000).to_i
        
        if data_exists
            inodes_used = du('--inodes', '--summarize', data_dir).to_i
            inodes_used = round_to(inodes_min, inodes_used)
        else
            inodes_used = inodes_min
        end
           
        inodes_used = fit_range(inodes_min, inodex_max, inodes_used)
        table_definition_cache = mysqld_tune.fetch('table_definition_cache', inodes_used)
        table_open_cache = mysqld_tune.fetch('table_open_cache', inodes_used)
        #---
        
        # with safe limit
        open_file_limit_roundto = cfdb_settings.fetch('open_file_limit_roundto', 10000).to_i
        open_file_limit = 3 * (max_connections + table_definition_cache + table_open_cache)
        open_file_limit = round_to(open_file_limit_roundto, open_file_limit)
        
        
        # Complex tuning based on target DB size and available RAM
        #==================================================
        
        # target database size
        target_size = conf[:target_size]
        
        if target_size == 'auto'
            # we ignore other possible instances
            target_size = disk_size(root_dir)
        end
        
        mb = 1024 * 1024
        gb = mb * 1024
        
        max_binlog_files = mysqld_tune.fetch('max_binlog_files', 20).to_i
        binlog_reserve_percent = cfdb_settings.fetch('binlog_reserve_percent', 10).to_i
        binlog_reserve = target_size * binlog_reserve_percent / 100
        
        if binlog_reserve < (max_binlog_files * gb)
            max_binlog_size = 256 * mb
        else
            max_binlog_size = gb
        end
        
        avail_mem = get_memory(cluster) * mb
        
        #
        default_chunk_size = cfdb_settings.fetch('default_chunk_size', 2 * gb).to_i
        max_pools = 64 # MySQL limit

        innodb_buffer_pool_size_percent= cfdb_settings.fetch('innodb_buffer_pool_size_percent', 80).to_i
        innodb_buffer_pool_size = (avail_mem * innodb_buffer_pool_size_percent / 100).to_i
        innodb_buffer_pool_chunk_size = default_chunk_size
        gcs_recv_q_hard_limit = (avail_mem - innodb_buffer_pool_size) / 2
        
        if innodb_buffer_pool_size > (max_pools * innodb_buffer_pool_chunk_size)
            innodb_buffer_pool_roundto = cfdb_settings.fetch('innodb_buffer_pool_roundto', gb).to_i
            innodb_buffer_pool_chunk_size = round_to(innodb_buffer_pool_roundto, innodb_buffer_pool_size / max_pools)
            innodb_buffer_pool_size = innodb_buffer_pool_chunk_size * max_pools
            innodb_buffer_pool_instances = max_pools
            innodb_sort_buffer_size = 64 * mb
        elsif innodb_buffer_pool_size > innodb_buffer_pool_chunk_size
            innodb_buffer_pool_roundto = cfdb_settings.fetch('innodb_buffer_pool_roundto', 128 * mb).to_i
            innodb_buffer_pool_instances = innodb_buffer_pool_size / innodb_buffer_pool_chunk_size
            innodb_buffer_pool_instances = fit_range(1, max_pools, innodb_buffer_pool_instances)
            
            if innodb_buffer_pool_instances > 1
                innodb_buffer_pool_chunk_size = round_to(innodb_buffer_pool_roundto, innodb_buffer_pool_chunk_size)
                innodb_buffer_pool_size = innodb_buffer_pool_chunk_size * innodb_buffer_pool_instances
            else
                innodb_buffer_pool_chunk_size = innodb_buffer_pool_size
            end
            innodb_sort_buffer_size = 16 * mb
        else
            innodb_buffer_pool_chunk_size = innodb_buffer_pool_size
            innodb_buffer_pool_instances = 1
            innodb_sort_buffer_size = mb
        end
        
        if (target_size > (100 * gb)) and (avail_mem > (4*gb))
            innodb_log_file_size = '1G'
            innodb_log_buffer_size = '64M'
            gcache_size = fit_range( 1, 100, target_size / 20 / 1024 )
            gcache_size = "#{gcache_size}G"
        elsif (target_size > (10 * gb)) and (avail_mem > (gb))
            innodb_log_file_size = '128M'
            innodb_log_buffer_size = '32M'
            gcache_size = fit_range( 128, 5120, target_size / 20 )
            gcache_size = "#{gcache_size}M"
        else
            innodb_log_file_size = '16M'
            innodb_log_buffer_size = '8M'
            gcache_size = '128M'
        end
        
        innodb_thread_concurrency = fit_range(4, 64, Facter['processors'].value['count'] * 2 + 2)
        
        if optimize_ssd
            innodb_io_capacity = 10000
            innodb_io_capacity_max = 100000
        else
            innodb_io_capacity = 300
            innodb_io_capacity_max = 2000
        end
        #==================================================
        
        
        # Prepare mysql client conf
        #---
        client_settings = {
            'client' => {
                'user' => 'root',
                'host' => 'localhost',
                'password' => root_pass,
                'socket' => sock_file,
            }
        }
        cf_system.atomicWriteIni(client_conf_file, client_settings, { :user => user})
        
        # Make sure we have root password always set
        #---
        if is_56
            setup_sql = [
                "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('#{root_pass}');",
                'FLUSH PRIVILEGES;',
            ]
        else
            setup_sql = [
                "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '#{root_pass}';",
                'FLUSH PRIVILEGES;',
            ]
        end
        cf_system.atomicWrite(init_file, setup_sql.join("\n"), { :user => user})
        
        # Prepare conf
        #---
        
        # defaults
        conf_settings = {
            'mysqld' => {
                'character_set_server' => 'utf8',
                'enforce_gtid_consistency' => 'ON',
                'expire_logs_days' => 7,
                'gtid_mode' => 'ON',
                'init_file' => init_file,
                'innodb_buffer_pool_instances' => innodb_buffer_pool_instances,
                'innodb_buffer_pool_size' => innodb_buffer_pool_size,
                'innodb_file_format' => 'Barracuda',
                'innodb_file_per_table' => 'ON',
                'innodb_flush_log_at_trx_commit' => 2,
                'innodb_io_capacity' => innodb_io_capacity,
                'innodb_io_capacity_max' => innodb_io_capacity_max,
                'innodb_log_buffer_size' => innodb_log_buffer_size,
                'innodb_log_file_size' => innodb_log_file_size,
                'innodb_sort_buffer_size' => innodb_sort_buffer_size,
                'innodb_strict_mode' => 'ON',
                'innodb_thread_concurrency' => innodb_thread_concurrency,
                'log_bin' => "#{data_dir}/#{cluster}#{server_id}-bin",
                'log_slave_updates' => 'TRUE',
                'max_binlog_size' => max_binlog_size,
                'max_binlog_files' => max_binlog_files,
                'max_connections' => max_connections,
                'performance_schema' => 'OFF',
                'server_id' => server_id,
                'ssl_ca' => "#{pki_dir}/ca.crt",
                'ssl_cert' => "#{pki_dir}/local.crt",
                #'ssl_cipher' => '',
                'ssl_crl' => "#{pki_dir}/crl.crt",
                'ssl_key' => "#{pki_dir}/local.key",
                'table_definition_cache' => table_definition_cache,
                'table_open_cache' => table_open_cache,
                'thread_handling' => 'pool-of-threads',
                'thread_pool_size' => innodb_thread_concurrency,
                'thread_pool_max_threads' => max_connections,
                #'tls_version' => 'TLSv1.2',
                'transaction_isolation' => 'READ-COMMITTED',
            },
            'client' => client_settings['client'],
            'xtrabackup' => {
                'use-memory' => avail_mem,
            }
        }
        
        mysqld_settings = conf_settings['mysqld']
        
        if is_57
            mysqld_settings['innodb_buffer_pool_chunk_size'] = innodb_buffer_pool_chunk_size
        end
        
        if is_cluster
            mysqld_settings['wsrep_provider'] = '/usr/lib/libgalera_smm.so'
            if (data_exists or is_secondary) and !is_bootstrap
                cluster_addr_mapped = cluster_addr.map do |v|
                    next if v['is_arbitrator'] && !is_arbitrator
                    
                    peer_addr = v['addr']
                    peer_port = v['port'].to_i + GALERA_PORT_OFFSET
                    
                    if !secure_cluster and IPAddr.new(peer_addr).ipv6?
                        "[#{peer_addr}]:#{peer_port}"
                    else
                        "#{peer_addr}:#{peer_port}"
                    end
                end
                cluster_addr_mapped.reject! { |v| v.nil? }
                mysqld_settings['wsrep_cluster_address'] = 'gcomm://' + cluster_addr_mapped.sort().join(',')
            else
                mysqld_settings['wsrep_cluster_address'] = 'gcomm://'
            end
            mysqld_settings['wsrep_forced_binlog_format'] = 'ROW'
            mysqld_settings['wsrep_replicate_myisam'] = 'OFF'
            mysqld_settings['wsrep_retry_autocommit'] = 1
            mysqld_settings['wsrep_slave_threads'] = innodb_thread_concurrency
            mysqld_settings['wsrep_sst_auth'] = "root:#{root_pass}"
            mysqld_settings['wsrep_sst_donor_rejects_queries'] = 'OFF'
            mysqld_settings['wsrep_sst_method'] = 'xtrabackup-v2'
            
            # make sure we don't get surprises when these defaults change
            conf_settings['sst'] = {
                'streamfmt' => 'xbstream',
                'transferfmt' => 'socat',
                'encrypt' => 0,
            }
            
            if secure_cluster
                socat_pem_file = "#{pki_dir}/socat.pem"
                
                conf_settings['sst'].merge!({
                    # use openssl encryption
                    'encrypt' => 2,
                    'tca' => mysqld_settings['ssl_ca'],
                    'tcert' => socat_pem_file,
                })
                    
                local_pem = File.read("#{pki_dir}/local.key") + File.read("#{pki_dir}/local.crt")
                cf_system.atomicWrite(socat_pem_file, local_pem, {:user => user, :show_diff => false})
            end
        end
        
        # tunes
        settings_tune.each do |k, v|
            next if k == 'cfdb'
            conf_settings[k] = {} if not conf_settings.has_key? k
            conf_settings[k].merge! v
        end

        
        # forced
        forced_settings = {
            'bind_address' => bind_address,
            'binlog_format' => 'ROW',
            'datadir' => data_dir,
            'default_storage_engine' => 'InnoDB',
            'default_time_zone' => '+00:00',
            'memlock' => 'TRUE',
            'open_files_limit' => open_file_limit,
            'pid_file' => pid_file,
            'port' => port,
            'safe_user_create' => 'TRUE',
            'secure_auth' => 'ON',
            'secure_file_priv' => tmp_dir,
            'skip_name_resolve' => 'ON',
            'socket' => sock_file,
            'tmpdir' => tmp_dir,
            'user' => user,
            '# major version' => version,
        }
        
        if is_cluster
            wsrep_provider_options = {
                # should not harm even with low latency
                'evs.send_window' => 512,
                'evs.user_send_window' => 512,
                'evs.version' => 1,
                'gcache.size' => gcache_size,
                'gcache.recover' => 'YES',
                # testing is required
                #'gcomm.thread_prio' => 'rr:2',
                'gcs.fc_factor' => '1.0',
                # out of range with 1.0
                'gcs.max_throttle' => '0.9999',
                'gcs.recv_q_hard_limit' => gcs_recv_q_hard_limit,
                # should not be a problem with xtrabackup
                'gcs.sync_donor' => 'YES',
                # support auto-heal
                'pc.recovery' => 'TRUE',
                'pc.wait_prim' => 'TRUE',
                'pc.wait_prim_timeout' => 'PT60M',
                # may lead to problems
                'repl.commit_order' => 1,
                'socket.checksum' => 2,
            }
            wsrep_provider_options.merge! cfdb_settings.fetch('wsrep_provider_options', {})
            
            # Forced settings
            #--
            if secure_cluster
                wsrep_provider_options['socket.ssl'] = 'YES'
                wsrep_provider_options['socket.ssl_ca'] = mysqld_settings['ssl_ca']
                wsrep_provider_options['socket.ssl_cert'] = mysqld_settings['ssl_cert']
                wsrep_provider_options['socket.ssl_key'] = mysqld_settings['ssl_key']
                # known bug https://github.com/codership/galera/issues/399
                wsrep_provider_options['socket.ssl_cipher'] = 'AES128-SHA'
                wsrep_addr = Puppet[:certname]
            else
                wsrep_addr = bind_address
            end
            
            wsrep_provider_options['ist.recv_addr'] = "#{wsrep_addr}:#{ist_port}"
            
            if is_bootstrap
                wsrep_provider_options['pc.bootstrap'] = 'YES'
            else
                wsrep_provider_options['pc.bootstrap'] = 'NO'
            end
            
            #--
            forced_settings['innodb_autoinc_lock_mode'] = 2
            
            forced_settings['wsrep_cluster_name'] = cluster
            forced_settings['wsrep_node_address'] = "#{wsrep_addr}:#{galera_port}"
            forced_settings['wsrep_node_incoming_address'] = "#{bind_address}:#{port}"
            forced_settings['wsrep_sst_receive_address'] = "#{wsrep_addr}:#{sst_port}"
            forced_settings['wsrep_provider_options'] = wsrep_provider_options.map{|k,v| "#{k}=#{v}"}.join('; ')
            
            if is_arbitrator
                wsrep_provider_options['gmcast.listen_addr'] = "tcp://#{wsrep_addr}:#{galera_port}"
                
                wsrep_provider_options.keys().each do |k|
                    if /^(repl|gcache|ist)\./.match k
                        wsrep_provider_options.delete k
                    end
                end
                
                garbd_settings = {
                    'group' => cluster,
                    'address' => mysqld_settings['wsrep_cluster_address'],
                    'options' => wsrep_provider_options.map{|k,v| "#{k}=#{v}"}.join(';')
                }
                
            end
        end
        
        mysqld_settings.merge! forced_settings
        
        if is_arbitrator
            config_file_changed = cf_system.atomicWriteEnv(garbd_conf_file, garbd_settings, { :user => user})
        else
            config_file_changed = cf_system.atomicWriteIni(conf_file, conf_settings, { :user => user})
        end
        
        # Prepare service file
        #---
        if is_arbitrator
            service_ini = {
                'LimitNOFILE' => 1024,
                'ExecStart' => "#{GARBD} --cfg #{garbd_conf_file}",
                'ExecStartPost' => "/bin/rm -f #{restart_required_file}",
            }
            service_env = {}
            service_changed = create_service(conf, service_ini, service_env)
        else
            service_ini = {
                'LimitNOFILE' => open_file_limit * 2,
                'ExecStart' => "#{MYSQLD} --defaults-file=#{conf_dir}/mysql.cnf $MYSQLD_OPTS",
                'ExecStartPost' => "/bin/rm -f #{restart_required_file}",
                'ExecReload' => "#{MYSQLADMIN} refresh",
                'ExecStop' => "#{MYSQLADMIN} shutdown",
                'OOMScoreAdjust' => -200,
            }
            service_env = {
                'MYSQLD_OPTS' => '',
            }
            service_changed = create_service(conf, service_ini, service_env)
        end
        
        config_changed = config_file_changed || service_changed
        
        # Prepare data dir
        #---
        
        if is_arbitrator
            if config_changed
                FileUtils.touch(restart_required_file)
                FileUtils.chown(user, user, restart_required_file)
            end
            
            if !data_exists
                FileUtils.mkdir(data_dir, :mode => 0750)
                FileUtils.chown(user, user, data_dir)
                
                FileUtils.touch(restart_required_file)
                FileUtils.chown(user, user, restart_required_file)
                
                systemctl('start', "#{service_name}.service")
            elsif File.exists?(restart_required_file)
                warning("#{user} configuration update. Service restart is required!")
                warning("Please run when safe: /bin/systemctl restart #{service_name}.service")
            end
        elsif data_exists
            if !File.exists?(upgrade_file) or (upgrade_ver != File.read(upgrade_file))
                # if version comment changed or second run 
                if config_file_changed or File.exists?(restart_required_file)
                    warning("#{user} please restart before mysql_upgrade can run!")
                    warning("Please run when safe: /bin/systemctl restart #{service_name}.service")

                    # There is a possible security issue, if rogue users run on the same host
                    service_ini['ExecStartPre'] = "/bin/chmod 700 #{run_dir}"
                    service_env['MYSQLD_OPTS'] = [
                        '--skip-networking',
                        '--skip-grant-tables',
                        '--init-file=',
                    ].join(' ')
                    
                    if is_cluster
                        service_env['MYSQLD_OPTS'] += ' --wsrep-provider=none'
                    end
                    
                    create_service(conf, service_ini, service_env)
                else
                    systemctl('start', "#{service_name}.service")
                    wait_sock(service_name, sock_file)
                    
                    warning('> running mysql upgrade')
                    sudo('-H', '-u', user, MYSQL_UPGRADE, '--force', '--skip-version-check')

                    cf_system.atomicWrite(upgrade_file, upgrade_ver, {:user => user})
                    config_changed = true
                end
            end
            
            if config_changed
                debug('Updating max_connections in runtime')
                begin
                    sudo('-H', '-u', user, MYSQL, '--wait', '-e',
                        "SET GLOBAL max_connections = #{max_connections};")
                rescue
                    warning('Failed to update max_connections in runtime')
                end
                
                FileUtils.touch(restart_required_file)
                FileUtils.chown(user, user, restart_required_file)
            end
            
            if File.exists?(restart_required_file)
                warning("#{user} configuration update. Service restart is required!")
                warning("Please run when safe: /bin/systemctl restart #{service_name}.service")
            end
        elsif is_secondary
            if is_cluster
                # do nothing, to be copied on startup
                #FileUtils.mkdir(data_dir, :mode => 0750)
                #FileUtils.chown(user, user, data_dir)
                service_ini['ExecStartPre'] = "/bin/mkdir -p #{data_dir}"
                create_service(conf, service_ini, service_env)
                
                FileUtils.touch(restart_required_file)
                FileUtils.chown(user, user, restart_required_file)
                cf_system.atomicWrite(upgrade_file, upgrade_ver, {:user => user})
                
                fw_configured = cluster_addr.reduce(true) do |m, v|
                    begin
                        unless v['is_arbitrator']
                            sudo('-H', '-u', user, '/usr/bin/ssh', v['addr'], 'hostname')
                        end
                        m
                    rescue => e
                        false
                    end
                end
                
                if fw_configured
                    warning("> starting JOINER node (this may take time)")
                    systemctl('start', "#{service_name}.service")
                    wait_sock(service_name, sock_file, cfdb_settings.fetch('joiner_timeout', 600))
                else
                    warning("JOINER node can start AFTER firewall is configured on active nodes. Please re-provision them.")
                end
            else
                # need to manually initialize data_dir from master
                raise Puppet::DevError, "MySQL slave is not supported.\nPlease use more reliable is_cluster setup."
            end
        elsif init_db_from and !init_db_from.empty?
            warning("> copying from #{init_db_from}")
            FileUtils.cp_r(init_db_from, data_dir)
            FileUtils.chown_R(user, user, data_dir)
            
            warning("> starting service")
            systemctl('start', "#{service_name}.service")
            wait_sock(service_name, sock_file)
            
            warning('> running mysql upgrade')
            sudo('-H', '-u', user, MYSQL_UPGRADE, '--force')
            cf_system.atomicWrite(upgrade_file, upgrade_ver, {:user => user})
            
        else
            have_initialize = sudo('-u', user, MYSQLD, '--verbose', '--help')
            have_initialize = /--initialize/.match(have_initialize)
            have_initialize = !have_initialize.nil?
            
            if have_initialize
                warning('> running mysql initialize')
                create_service(
                    conf,
                    service_ini,
                    service_env.merge({ 'MYSQLD_OPTS' => '--initialize' })
                )
                systemctl('start', "#{service_name}.service")
                
                # return to normal
                create_service(conf, service_ini, service_env)
            else
                warning('> running mysql install db')
                sudo('-u', user, MYSQL_INSTALL_DB,
                    "--defaults-file=#{conf_file}",
                    "--datadir=#{data_dir}")
                systemctl('start', "#{service_name}.service")
            end
            
            wait_sock(service_name, sock_file)
            
            if !File.exists? data_dir or !File.exists? sock_file
                raise Puppet::DevError, "Failed to initialize #{data_dir}"
            end
            
            # no need to upgrade just initialized instance
            cf_system.atomicWrite(upgrade_file, upgrade_ver, {:user => user})
        end
        
        # Check cluster is complete
        #---
        check_cluster_mysql(conf)
    end
    
    def check_cluster_mysql(conf)
        return true if !conf[:is_cluster] or conf[:is_arbitrator]
        
        begin
            cluster_size = 1  + conf[:cluster_addr].size()
            res = sudo('-H', '-u', conf[:user], MYSQL,
                       '--batch', '--skip-column-names', '--wait', '-e',
                       "SHOW STATUS LIKE 'wsrep_cluster_size';")
            fact_cluster_size = res.split()[1].to_i
            
            if fact_cluster_size != cluster_size
                cluster = conf[:cluster]
                warning("> cluster #{cluster} is incomplete #{fact_cluster_size}/#{cluster_size}")
            end
            
            true
        rescue => e
            warning(e)
            #warning(e.backtrace)
            false
        end
    end
end
