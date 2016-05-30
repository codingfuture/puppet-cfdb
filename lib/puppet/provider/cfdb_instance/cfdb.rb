
# Done this way due to some weird behavior in tests also ignoring $LOAD_PATH
begin
    require File.expand_path( '../../../../puppet_x/cf_system/provider_base', __FILE__ )
rescue LoadError
    require File.expand_path( '../../../../../../cfsystem/lib/puppet_x/cf_system/provider_base', __FILE__ )
end


require 'fileutils'

Puppet::Type.type(:cfdb_instance).provide(
    :cfdb,
    :parent => PuppetX::CfSystem::ProviderBase
) do
    desc "Provider for cfdb_instance"
    
    commands :sudo => '/usr/bin/sudo'
    commands :systemctl => '/bin/systemctl'
    commands :df => '/bin/df'
    commands :du => '/usr/bin/du'
    
    MYSQL = '/usr/bin/mysql' unless defined? MYSQL
    MYSQLD = '/usr/sbin/mysqld' unless defined? MYSQLD
    MYSQLADMIN = '/usr/bin/mysqladmin' unless defined? MYSQLADMIN
    MYSQL_INSTALL_DB = '/usr/bin/mysql_install_db' unless defined? MYSQL_INSTALL_DB
    MYSQL_UPGRADE = '/usr/bin/mysql_upgrade' unless defined? MYSQL_UPGRADE
    GARBD = '/usr/bin/garbd' unless defined? GARBD
    
    GALERA_PORT_OFFSET = 100 unless defined? GALERA_PORT_OFFSET
    SST_PORT_OFFSET = 200 unless defined? SST_PORT_OFFSET
    IST_PORT_OFFSET = 300 unless defined? IST_PORT_OFFSET

    def self.get_config_index
        'cf10db1_instance'
    end

    def self.get_generator_version
        cf_system().makeVersion(__FILE__)
    end
    
    def self.check_exists(params)
        File.exists?(params[:root_dir] + '/data')
    end
   
    def self.on_config_change(newconf)
        newconf.each do |name, conf|
            db_type = conf[:type]
            self.send("create_#{db_type}", conf)
        end
    end
    
    def self.fit_range(min, max, val)
        return [min, [max, val].min].max
    end
    
    def self.round_to(to, val)
        return (((val + to) / to).to_i * to).to_i
    end
    
    def self.create_service(conf, service_ini, service_env)
        db_type = conf[:type]
        service_name = conf[:service_name]
        service_file = "/etc/systemd/system/#{service_name}.service"
        env_file = "/etc/default/#{service_name}.conf"
        user = conf[:user]
        
        mem_limit = cf_system.getMemory(conf[:cluster])
        
        #---
        content_env = {
            'CFDB_ROOT_DIR' => conf[:root_dir],
        }
        
        content_env.merge! service_env
        
        #---
        content_ini = {
            'Unit' => {
                'Description' => "CFDB instance: #{service_name}",
            },
            'Service' => {
                'LimitNOFILE' => 100000,
                'WorkingDirectory' => conf[:root_dir],
            },
        }
        
        content_ini['Service'].merge! service_ini
        
        #---
        self.cf_system().createService({
            :service_name => service_name,
            :user => user,
            :content_ini => content_ini,
            :content_env => content_env,
            :cpu_weight => conf[:cpu_weight],
            :io_weight => conf[:io_weight],
            :mem_limit => mem_limit,
            :mem_lock => true,
        })
    end
    
    def self.disk_size(dir)
        ret = df('-BM', '--output=size', dir)
        ret = ret.split("\n")
        ret[1].strip().to_i
    end
    
    def self.is_hdd(dir)
        ret = df('-BM', '--output=source', dir)
        ret = ret.split("\n")
        device = ret[1].strip()
        
        if not File.exists?(device)
            debug("Device not found #{device}")
            # assume something with high IOPS
            return false
        end
        
        if File.symlink?(device)
            device = File.readlink(device)
        end
        
        device = File.basename(device)
        
        begin
            device.gsub!(/[0-9]/, '')
            rotational = File.read("/sys/block/#{device}/queue/rotational").to_i
            debug("Device #{device} rotational = #{rotational}")
            return rotational.to_i == 1
        rescue => e
            warning(e)
             # assume something with high IOPS
            return false
        end
    end
    
    #==================================
    def self.create_mysql(conf)
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
        
        root_pass = cf_system.genSecret(cluster)
        
        data_exists = File.exists?(data_dir)
        
        if cfdb_settings.has_key? 'optimize_ssd'
            optimize_ssd = cfdb_settings['optimize_ssd']
        else
            optimize_ssd = !is_hdd(root_dir)
        end
        
        secure_cluster = cfdb_settings.fetch('secure_cluster', false)
        
        #---
        if is_arbitrator
            is_56 = true
            is_57 = false
            upgrade_ver = 'NONE'
        else
            ver_parts = version.split('.')
            is_56 = (ver_parts[0] == '5' and ver_parts[1] == '6')
            is_57 = (ver_parts[0] == '5' and ver_parts[1] == '7')
            
            if is_57
                upgrade_ver = sudo('-u', user, MYSQL_UPGRADE, '--version')
            else
                upgrade_ver = sudo('-u', user, MYSQL_UPGRADE, '--help').split("\n")[0]
            end
        end
        
        # calculate based on user access list x limit
        #---
        max_connections = 10
        have_external_conn = false
        role_index = Puppet::Type.type(:cfdb_role).provider(:cfdb).get_config_index
        roles = cf_system().config.get_new(role_index)
        
        if roles
            roles.each do |k, v|
                if v[:cluster] == cluster
                    max_connections += v[:allowed_hosts].values.inject(0, :+)
                    
                    # check, if there is some other than locahost
                    have_external_conn = true if v[:allowed_hosts].length > 1
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
        
        max_binlog_files = cfdb_settings.fetch('max_binlog_files', 20).to_i
        binlog_reserve_percent = cfdb_settings.fetch('binlog_reserve_percent', 10).to_i
        binlog_reserve = target_size * binlog_reserve_percent / 100
        
        if binlog_reserve < (max_binlog_files * gb)
            max_binlog_size = 256 * mb
        else
            max_binlog_size = gb
        end
        
        avail_mem = cf_system.getMemory(cluster) * mb
        
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
            gcache_size = fit_range( 1, 100, target_size / 20 / gb )
            gcache_size = "#{gcache_size}G"
        elsif (target_size > (10 * gb)) and (avail_mem > (gb))
            innodb_log_file_size = '128M'
            innodb_log_buffer_size = '32M'
            gcache_size = fit_range( 128, 5120, target_size / 20 / mb )
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
        setup_sql = [
            "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('#{root_pass}');",
            'FLUSH PRIVILEGES;',
        ]
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
                    peer_addr = v['addr']
                    peer_port = v['port'].to_i + GALERA_PORT_OFFSET
                    
                    if !secure_cluster and IPAddr.new(peer_addr).ipv6?
                        "[#{peer_addr}]:#{peer_port}"
                    else
                        "#{peer_addr}:#{peer_port}"
                    end
                end
                mysqld_settings['wsrep_cluster_address'] = 'gcomm://' + cluster_addr_mapped.sort().join(',')
            else
                mysqld_settings['wsrep_cluster_address'] = 'gcomm://'
            end
            mysqld_settings['wsrep_forced_binlog_format'] = 'ROW'
            mysqld_settings['wsrep_replicate_myisam'] = 'ON'
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
                
                if !File.exists?(socat_pem_file) or (File.read(socat_pem_file) != local_pem)
                    cf_system.atomicWrite(socat_pem_file, local_pem, {:user => user})
                end
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
        }
        
        if is_cluster
            wsrep_provider_options = {
                # should not harm even with low latency
                'evs.send_window' => 512,
                'evs.user_send_window' => 512,
                'evs.version' => 1,
                'gcache.size' => gcache_size,
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
            config_changed = cf_system.atomicWriteEnv(garbd_conf_file, garbd_settings, { :user => user})
        else
            config_changed = cf_system.atomicWriteIni(conf_file, conf_settings, { :user => user})
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
            }
            service_env = {
                'MYSQLD_OPTS' => '',
            }
            service_changed = create_service(conf, service_ini, service_env)
        end
        
        config_changed ||= service_changed
        
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
                
                warning("JOINER arbitrator must be started manually AFTER firewall is configured on active nodes")
                warning("Please run when safe: /bin/systemctl start #{service_name}.service")
            elsif File.exists?(restart_required_file)
                warning("#{user} configuration update. Service restart is required!")
                warning("Please run when safe: /bin/systemctl restart #{service_name}.service")
            end
        elsif data_exists
            if !File.exists?(upgrade_file) or (upgrade_ver != File.read(upgrade_file))
                systemctl('start', "#{service_name}.service")
                if not is_secondary
                    warning('> running mysql upgrade')
                    sudo('-u', user, MYSQL_UPGRADE, '--force')
                end
                cf_system.atomicWrite(upgrade_file, upgrade_ver, {:user => user})
            end
            
            if config_changed
                debug('Updating max_connections in runtime')
                begin
                    sudo('-u', user, MYSQL, '--wait', '-e',
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
                FileUtils.mkdir(data_dir, :mode => 0750)
                FileUtils.chown(user, user, data_dir)
                
                FileUtils.touch(restart_required_file)
                FileUtils.chown(user, user, restart_required_file)
                
                warning("JOINER node must be started manually AFTER firewall is configured on active nodes")
                warning("Please run when safe: /bin/systemctl start #{service_name}.service")
            else
                # need to manually initialize data_dir from master
                raise Puppet::DevError, "MySQL slave is not supported.\nPlease use more reliable is_cluster setup."
            end
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
            
            for i in 1..30
                break if File.exists? sock_file
                warning("Waiting #{service_name} startup (#{i})!")
                sleep 1
            end
            
            if not File.exists? data_dir or not File.exists? sock_file
                raise Puppet::DevError, "Failed to initialize #{data_dir}"
            end
            
            # no need to upgrade just initialized instance
            cf_system.atomicWrite(upgrade_file, upgrade_ver, {:user => user})
        end
    end
    
    #==================================
    def self.create_postgresql(conf)
        debug('create_postgresql')
        cf_system = self.cf_system()
        
        root_dir = conf[:root_dir]
        conf_dir = "#{root_dir}/conf"
        root_data_dir = "#{root_dir}/data"
        tmp_dir = "#{root_dir}/tmp"
        pki_dir = "#{root_dir}/pki/puppet"
        
        cluster = conf[:cluster]
        service_name = conf[:service_name]
        version = conf[:version]
        is_secondary = conf[:is_secondary]
        is_cluster = conf[:is_cluster]
        is_arbitrator = conf[:is_arbitrator]
        cluster_addr = conf[:cluster_addr]
        type = conf[:type]
        conf_file = "#{conf_dir}/postgresql.conf"
        hba_file = "#{conf_dir}/pg_hba.conf"
        ident_file = "#{conf_dir}/pg_ident.conf"
        client_conf_file = "#{root_dir}/.pg_service.conf"
        pgpass_file = "#{root_dir}/.pgpass"
        
        data_dir = "#{root_data_dir}/#{version}"
        active_version_file = "#{conf_dir}/active_version"
        unclean_state_file = "#{conf_dir}/unclean_state"
        pg_bin_dir = "/usr/lib/postgresql/#{version}/bin"
        run_dir = "/run/#{service_name}"
        sock_file = "#{run_dir}/service.sock"
        pid_file = "#{run_dir}/service.pid"
        restart_required_file = "#{conf_dir}/restart_required"

        user = conf[:user]
        settings_tune = conf[:settings_tune]
        is_bootstrap = conf[:is_bootstrap]
        cfdb_settings = settings_tune.fetch('cfdb', {})
        postgresql_tune = settings_tune.fetch('postgresql', {})
        
        root_pass = cf_system.genSecret(cluster)
        
        data_exists = (
            File.exists?(root_data_dir) and
            File.exists?(data_dir) and
            File.exists?(active_version_file) and
            (File.read(active_version_file) == version)
        )
        
        if cfdb_settings.has_key? 'optimize_ssd'
            optimize_ssd = cfdb_settings['optimize_ssd']
        else
            optimize_ssd = !is_hdd(root_dir)
        end
        
        secure_cluster = cfdb_settings.fetch('secure_cluster', false)
        
        ver_parts = version.split('.')
        is_94 = (ver_parts[0] == '9' and ver_parts[1] == '4')
        is_95 = (ver_parts[0] == '9' and ver_parts[1] == '5')
        
        
        # calculate based on user access list x limit
        #---
        superuser_reserved_connections = 10
        max_connections = superuser_reserved_connections
        have_external_conn = false
        role_index = Puppet::Type.type(:cfdb_role).provider(:cfdb).get_config_index
        roles = cf_system().config.get_new(role_index)
        hba_content = []
        hba_content << ['local', 'all', 'all', 'md5']
        hba_content << ['local', 'all', user, 'ident']
        hba_host_roles = {}
        
        if roles
            roles.each do |k, v|
                if v[:cluster] == cluster
                    v.each do |host, max_conn|
                        max_connections += max_conn
                        
                        if host != 'localhost'
                            have_external_conn = true
                            hba_host_roles[host] ||= []
                            hba_host_roles[host] << v[:role]
                        end
                    end
                end
            end
            
            if cfdb_settings.fetch('strict_hba_roles', false)
                hba_host_roles.each do |host, host_roles|
                    hba_content << ['local', 'all', host_roles.join(','), host, 'md5']
                end
            else
                 hba_host_roles.keys.each do |host|
                    hba_content << ['local', 'all', 'all', host, 'md5']
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
        #---
        
        # with safe limit
        open_file_limit_roundto = cfdb_settings.fetch('open_file_limit_roundto', 10000).to_i
        open_file_limit = 3 * (max_connections + inodes_used)
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
        
        avail_mem = cf_system.getMemory(cluster)
        
        #

        shared_buffers_percent = cfdb_settings.fetch('shared_buffers_percent', 20).to_i
        temp_buffers_percent = cfdb_settings.fetch('temp_buffers_percent', 40).to_i
        temp_buffers_overcommit = cfdb_settings.fetch('temp_buffers_overcommit', 8).to_i
        shared_buffers = (avail_mem * shared_buffers_percent / 100).to_i
        
        
        temp_buffers = (avail_mem * temp_buffers_overcommit * temp_buffers_percent / 100.0 / max_connections).to_i

        if temp_buffers < 1
            temp_buffers = "1MB"
        else
            temp_buffers = "#{temp_buffers}MB"
        end
        
        if avail_mem > 8192
            work_mem = '16MB'
            maintenance_work_mem = '512MB'
            wal_buffers = '256MB'
        elsif avail_mem > 2048
            work_mem = '4MB'
            maintenance_work_mem = '256MB'
            wal_buffers = '64MB'
        elsif avail_mem > 512
            work_mem = '2MB'
            maintenance_work_mem = '64MB'
            wal_buffers = '16MB'
        else
            work_mem = '2MB'
            maintenance_work_mem = '16MB'
            wal_buffers = '8MB'
        end
        
        if optimize_ssd
            effective_io_concurrency = (10000 / max_connections).to_i
        else
            effective_io_concurrency = (1000 / max_connections).to_i
        end
        
        max_wal_size = (target_size / 10 / mb).to_i
        min_wal_size = (target_size / 20 / mb).to_i
        
        #==================================================
        pgsettings = {
            # Resources
            #---
            'shared_buffers' => "#{shared_buffers}MB",
            'huge_pages' => 'off',
            'temp_buffers' => temp_buffers,
            'max_prepared_transactions' => max_connections,
            'work_mem' => work_mem,
            'maintenance_work_mem' => maintenance_work_mem,
            'dynamic_shared_memory_type' => 'posix',
            'temp_file_limit' => -1,
            'bgwriter_delay' => 50,
            'effective_io_concurrency' => effective_io_concurrency,
            'max_worker_processes' => Facter['processors'].value['count'],
            
            # Write Ahead Log
            #---
            'wal_level' => 'hot_standby',
            'fsync' => 'on',
            'synchronous_commit' => 'off',
            'wal_sync_method' => 'fdatasync',
            'full_page_writes' => 'on',
            'wal_compression' => 'on',
            'wal_buffers' => wal_buffers,
            'commit_delay' => 1000,
            'commit_siblings' => 1,
            'checkpoint_timeout' => '10min',
            'max_wal_size' => "#{max_wal_size}MB",
            'min_wal_size' => "#{min_wal_size}MB",
            
            # Autovacuum,
            'autovacuum' => 'on',
        }
            
        pgsettings.merge! postgresql_tune
        
        # forced settigns
        pgsettings.merge!({
            # Files
            #---
            'data_directory' => data_dir,
            'hba_file' => hba_file,
            'ident_file' => ident_file,
            'external_pid_file' => pid_file,
            # Connections & Auth
            #---
            'listen_addresses' => bind_address,
            'port' => port,
            'max_connections' => max_connections,
            'superuser_reserved_connections' => superuser_reserved_connections,
            'unix_socket_directories' => run_dir,
            'unix_socket_group' => user,
            'unix_socket_permissions' => '0777',
            'bonjour' => 'off',
            'ssl' => 'on',
            'ssl_ca_file' => "#{pki_dir}/ca.crt",
            'ssl_cert_file' => "#{pki_dir}/local.crt",
            'ssl_crl_file' => "#{pki_dir}/crl.crt",
            'ssl_key_file' => "#{pki_dir}/local.key",
            #'ssl_ciphers' =>
            'ssl_prefer_server_ciphers' => 'on',
            'db_user_namespace' => 'off',         
            # Resources
            #---
            'max_files_per_process' => open_file_limit,
                           
            # Logging
            #---
            'log_destination' => 'syslog',
            'syslog_ident' => service_name,
            'cluster_name' => service_name,
            'update_process_title' => 'off',
            # mantained by cluster or systemd (default)
            'restart_after_crash' => 'off',
        })
            
        if !is_95
            ['cluster_name',
             'min_wal_size',
             'max_wal_size',
             'wal_compression'].each do |v|
                pgsettings.delete v
            end
        end
        
        # Prepare client conf
        #---
        client_settings = {
            "#{service_name}" => {
                'host' => run_dir,
                'port' => port,
                'user' => user,
                'password' => root_pass,
                'dbname' => 'postgres',
            }
        }
        cf_system.atomicWriteIni(client_conf_file, client_settings, {:user => user})
        
        pgpass_content = "localhost:*:*:#{user}:#{root_pass}"
        cf_system.atomicWrite(pgpass_file, root_pass, {:user => user})

        #==================================================
        # config
        config_changed = self.atomicWritePG(conf_file, pgsettings, {:user => user})
        # hba
        hba_content = (hba_content.map{ |v| v.join(' ') }).join("\n")
        hba_changed = cf_system.atomicWrite(hba_file, hba_content, {:user => user})
        config_changed ||= hba_changed
        
        #service
        service_ini = {
            'LimitNOFILE' => open_file_limit * 2,
            'ExecStart' => "#{pg_bin_dir}/postgres --config_file=#{conf_file} $PGSQL_OPTS",
            'ExecStartPost' => "/bin/rm -f #{restart_required_file}",
            'ExecReload' => "#{pg_bin_dir}/pg_ctl -D #{data_dir} reload",
            'ExecStop' => "#{pg_bin_dir}/pg_ctl -D #{data_dir} stop -m fast",
        }
        service_env = {
            'PGSQL_OPTS' => '',
        }
        service_changed = create_service(conf, service_ini, service_env)

        config_changed ||= service_changed
      
        #---
        if File.exists?(unclean_state_file)
            warning("Something has gone wrong in previous runs!")
            warning("Please manually fix issues in #{root_dir} and then remove #{unclean_state_file}.")
        elsif data_exists
            if config_changed
                FileUtils.touch(restart_required_file)
                FileUtils.chown(user, user, restart_required_file)
                
                begin
                    systemctl('reload', "#{service_name}.service")
                rescue => e
                    warning("Failed to reload instance: #{e}")
                end
            end
            
            if File.exists?(restart_required_file)
                warning("#{user} configuration update. Service restart is required!")
                warning("Please run when safe: /bin/systemctl restart #{service_name}.service")
            end
            
        else
            warning('> running initdb')
            FileUtils.touch(unclean_state_file)
            #--
            
            FileUtils.mkdir_p(root_data_dir, :mode => 0750)
            FileUtils.chown(user, user, root_data_dir)
            FileUtils.rm_rf(data_dir)

            sudo('-u', user,
                 "#{pg_bin_dir}/initdb",
                 '--locale', cfdb_settings.fetch('locale', 'en_US.UTF-8'),
                 '--pwfile', pgpass_file,
                 '-D', data_dir)
            
            if File.exists?(active_version_file)
                warning('> migrating old data')
                old_version = File.read(active_version_file)
                old_data = "#{root_data_dir}/#{old_version}"
                old_pg_bin_dir = "/usr/lib/postgresql/#{version}/bin"
                
                sudo('-u', user,
                    "#{old_pg_bin_dir}/pg_ctl",
                    '-D', old_data,
                    'stop')
                sudo('-u', user,
                    "#{pg_bin_dir}/pg_ctl",
                    '-D', data_dir,
                    'stop')
                sudo('-u', user,
                    "#{pg_bin_dir}/pg_upgrade",
                    '-d', old_data,
                    '-D', data_dir,
                    '-b', old_pg_bin_dir,
                    '-B', pg_bin_dir)
                FileUtils.mv(old_data, "#{old_data}.bak")
            end
            
            cf_system.atomicWrite(active_version_file, version)
            #--
            FileUtils.rm_f(unclean_state_file)
            
            systemctl('start', "#{service_name}.service")
        end
    end
    
    def self.atomicWritePG(file, settings, opts={})
        content = []
        settings.each do |k, v|
            if v.is_a? String
                v = v.gsub("'", "''")
                content << "#{k} = '#{v}'"
            else
                content << "#{k} = #{v}"
            end
        end
        
        content = content.join("\n")
        
        self.cf_system.atomicWrite(file, content, opts)
    end    
end
