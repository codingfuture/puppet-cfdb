
module PuppetX::CfDb::PostgreSQL::Instance
    include PuppetX::CfDb::PostgreSQL
    
    def create_postgresql(conf)
        debug('create_postgresql')
        cf_system = self.cf_system()
        
        root_dir = conf[:root_dir]
        conf_dir = "#{root_dir}/conf"
        root_data_dir = "#{root_dir}/data"
        tmp_dir = "#{root_dir}/tmp"
        pki_dir = "#{root_dir}/pki/puppet"
        backup_dir = conf[:backup_dir]
        backup_wal_dir = "#{backup_dir}/log"
        
        cluster = conf[:cluster]
        service_name = conf[:service_name]
        repmgr_service_name = "#{service_name}-repmgr"
        version = conf[:version]
        is_secondary = conf[:is_secondary]
        is_cluster = conf[:is_cluster]
        is_arbitrator = conf[:is_arbitrator]
        cluster_addr = conf[:cluster_addr]
        access_list = conf[:access_list]
        type = conf[:type]
        conf_file = "#{conf_dir}/postgresql.conf"
        hba_file = "#{conf_dir}/pg_hba.conf"
        ident_file = "#{conf_dir}/pg_ident.conf"
        client_conf_file = "#{root_dir}/.pg_service.conf"
        pgpass_file = "#{root_dir}/.pgpass"
        repmgr_file = "#{conf_dir}/repmgr.conf"
        
        data_dir = "#{root_data_dir}/#{version}"
        active_version_file = "#{conf_dir}/active_version"
        unclean_state_file = "#{conf_dir}/unclean_state"
        pg_bin_dir = "/usr/lib/postgresql/#{version}/bin"
        run_dir = "/run/#{service_name}"
        pid_file = "#{run_dir}/service.pid"
        restart_required_file = "#{conf_dir}/restart_required"

        user = conf[:user]
        settings_tune = conf[:settings_tune]
        is_bootstrap = conf[:is_bootstrap]
        cfdb_settings = settings_tune.fetch('cfdb', {})
        postgresql_tune = settings_tune.fetch('postgresql', {})
        
        if is_secondary
            root_pass = cfdb_settings['shared_secret']
            cf_system.genSecret(cluster, ROOT_PASS_LEN, root_pass)
        else
            root_pass = cf_system.genSecret(cluster)
        end
        
        
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
        
        port = cf_system.genPort(cluster, cfdb_settings.fetch('port', nil))
        sock_file = "#{run_dir}/.s.PGSQL.#{port}"
        
        ver_parts = version.split('.')
        is_94 = (ver_parts[0] == '9' and ver_parts[1] == '4')
        is_95 = (ver_parts[0] == '9' and ver_parts[1] == '5')
        
        fqdn = Facter['fqdn'].value()
        
        
        # calculate based on user access list x limit
        #---
        superuser_reserved_connections = 10
        max_connections = superuser_reserved_connections
        max_replication_slots = 3
        have_external_conn = false
        hba_content = []
        hba_content << ['local', 'all', user, 'ident']
        hba_content << ['local', 'all', 'all', 'md5']
        hba_host_roles = {}
        
        access_list.each do |role_id, rinfo|
            rinfo.each do |v|
                host = v['host']
                max_conn = v['maxconn']
                max_connections += max_conn
                
                if host != fqdn
                    have_external_conn = true
                    hba_host_roles[host] ||= []
                    hba_host_roles[host] << role_id
                end
            end
        end
            
        if is_cluster
            cluster_addr = cluster_addr.clone
            cluster_addr << {
                'addr' => fqdn,
                'port' => port,
            }
            
            cluster_addr.each do |v|
                max_connections += 2
                max_replication_slots += 1
                
                host = v['addr']
                hba_host_roles[host] ||= []
                hba_host_roles[host] << REPMGR_USER
            end
            
            #---
            if is_secondary or is_arbitrator
                master_node = nil
                
                cluster_addr.each do |v|
                    next if v['addr'] == fqdn
                    next if v['is_secondary'] or v['is_arbitrator']
                    master_node = v
                    break
                end
                
                if master_node.nil?
                    err("No master node is known for #{cluster}")
                end
            end
        end
            
        strict_hba_roles = cfdb_settings.fetch('strict_hba_roles', true)

        hba_host_roles.each do |host, host_roles|
            begin
                host = Resolv.getaddress host
            rescue
            end
            
            begin
                if IPAddr.new(host).ipv6?
                    host = "#{host}/128"
                else
                    host = "#{host}/32"
                end
            rescue => e
                warning("Host #{host}")
                raise e
            end
            
            if strict_hba_roles
                hba_content << ['host', 'all', host_roles.join(','), host, 'md5']
            else
                hba_content << ['host', 'all', 'all', host, 'md5']
            end
            
            if host_roles.include? REPMGR_USER
                hba_content << ['host', 'replication', REPMGR_USER, host, 'md5']
            end
        end
        
        hba_content << []
        
        max_connections_roundto = cfdb_settings.fetch('max_connections_roundto', 100).to_i
        max_connections = round_to(max_connections_roundto, max_connections)
        #---
        
        #---
        if have_external_conn or is_cluster
            bind_address = cfdb_settings.fetch('listen', '0.0.0.0')
        else
            bind_address = '127.0.0.1'
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
        
        max_wal_size = (target_size / 10).to_i
        min_wal_size = (target_size / 20).to_i
        
        #==================================================
        pgpass_content = []
        pgpass_content << "localhost:*:*:#{user}:#{root_pass}"
        
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
            'max_connections' => max_connections,
            'max_replication_slots' => max_replication_slots,
            'superuser_reserved_connections' => superuser_reserved_connections,
            'max_worker_processes' => Facter['processors'].value['count'],
            
            # Write Ahead Log
            #---
            'wal_level' => 'archive',
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
            # Archiving
            'archive_mode' => 'on',
            'archive_command' => "mkdir -p \"#{backup_wal_dir}\" && test ! -f \"#{backup_wal_dir}/%f\" && cp \"%p\" \"#{backup_wal_dir}/%f\"",
            #'restore_command' => "cp \"#{backup_wal_dir}/%f\" \"%p\"",
            
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
        
        if is_cluster
            node_id = cfdb_settings.fetch('node_id', nil)
            upstream_node_id = cfdb_settings.fetch('upstream_node_id', nil)
            hostname = Facter['hostname'].value()
            
            sslrequire = ''
            sslrequire = 'sslmode=require' if secure_cluster
            
            if node_id.nil?
                node_id = hostname[/([0-9]+)$/, 1].to_i
                
                if node_id <= 0
                    fail("Either provide node_id in cfdb or make sure host name ends unique ID in cluster")
                end
            end
            
            pgpass_content << "*:*:*:#{REPMGR_USER}:#{root_pass}"
            
            pgsettings.merge!({
                'wal_level' => 'hot_standby',
                'wal_log_hints' => 'on',
                'hot_standby' => 'on',
                'archive_mode' => 'on',
                'max_wal_senders' => cluster_addr.size + 2,
                'shared_preload_libraries' => 'repmgr_funcs',
            })
            
            repmgr_conf = {
                'cluster' => cluster,
                'node' => node_id,
                'node_name' => fqdn,
                'conninfo' => "host=#{fqdn} port=#{port} user=#{REPMGR_USER} dbname=#{REPMGR_USER} #{sslrequire}",
                # repmgr uses the same for initdb
                'pg_ctl_options' => "-o \"--config_file=#{conf_file}\"",
                'pg_bindir' => pg_bin_dir,
            }
            
            if is_arbitrator
                repmgr_conf.merge!({
                    'pg_ctl_options' => "$(test -e #{active_version_file} && echo \"\" -o \"--config_file=#{conf_file}\")",
                })
            else
                repmgr_conf.merge!({
                    'use_replication_slots' => 1,
                    'pg_basebackup_options' => '--xlog-method=stream',
                    'failover' => 'automatic',
                    'promote_command' => "#{root_dir}/bin/cfdb_repmgr standby promote",
                    'follow_command' => "#{root_dir}/bin/cfdb_repmgr standby follow",
                })
            end
            
            if is_secondary
                if not upstream_node_id.nil?
                    repmgr_conf['upstream_node'] = upstream_node_id
                end
            end
        end
            
        if is_94
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
        cf_system.atomicWrite(pgpass_file, pgpass_content, {:user => user, :mode => 0600})
        
        #---
        FileUtils.touch(ident_file)
        FileUtils.chown(user, user, ident_file)

        #==================================================
        # config
        config_changed = self.atomicWritePG(conf_file, pgsettings, {:user => user})
        # hba
        hba_content = (hba_content.map{ |v| v.join(' ') }).join("\n")
        hba_changed = cf_system.atomicWrite(hba_file, hba_content, {:user => user})
        config_changed ||= hba_changed

        
        slice_name = "system-cfdb_#{cluster}"
        create_slice(slice_name, conf)
        
        if is_cluster
            # repmgr
            repmgr_changed = self.atomicWriteRepMgr(repmgr_file, repmgr_conf, {:user => user})
            
            #service
            service_ini = {
                'LimitNOFILE' => open_file_limit * 2,
                'ExecStart' => "#{REPMGRD} --config-file=#{repmgr_file}",
                'OOMScoreAdjust' => -200,
            }
        
            service_changed = create_service(conf, service_ini, {}, slice_name, repmgr_service_name)
            config_changed ||= service_changed
        end
        
        #service
        service_ini = {
            'LimitNOFILE' => open_file_limit * 2,
            'ExecStart' => "#{pg_bin_dir}/postgres --config_file=#{conf_file} $PGSQL_OPTS",
            'ExecStartPost' => "/bin/rm -f #{restart_required_file}",
            'ExecReload' => "#{pg_bin_dir}/pg_ctl -s -D #{data_dir} reload",
            'ExecStop' => "#{pg_bin_dir}/pg_ctl -s -D #{data_dir} stop -m fast",
            'OOMScoreAdjust' => -200,
        }
        service_env = {
            'PGSQL_OPTS' => '',
        }
    
        service_changed = create_service(conf, service_ini, service_env, slice_name)
        config_changed ||= service_changed
        
        #---
        if !File.exists? root_data_dir
            warning('> creating root data dir')
            FileUtils.mkdir_p(root_data_dir, :mode => 0750)
            FileUtils.chown(user, user, root_data_dir)
        end
        
        #---
        if File.exists?(unclean_state_file)
            warning("Something has gone wrong in previous runs!")
            warning("Please manually fix issues in #{root_dir} and then remove #{unclean_state_file}.")
            
        elsif data_exists
            if config_changed
                FileUtils.touch(restart_required_file)
                FileUtils.chown(user, user, restart_required_file)

                if not is_arbitrator
                    begin
                        warning("> reloading #{service_name}")
                        systemctl('reload', "#{service_name}.service")
                    rescue => e
                        warning("Failed to reload instance: #{e}")
                    end
                end
                
                if is_cluster and repmgr_changed
                    begin
                        warning("> restarting #{repmgr_service_name}")
                        systemctl('restart', "#{repmgr_service_name}.service")
                    rescue => e
                        warning("Failed to reload instance: #{e}")
                    end
                end
            end
            
            if File.exists?(restart_required_file)
                warning("#{user} configuration update. Service restart is required!")
                warning("Please run when safe: /bin/systemctl restart #{service_name}.service")
            end
            
        # No data: witness
        elsif is_arbitrator
            begin
                warning("> testing master connection #{master_node['addr']}")
                
                sudo('-H', '-u', user,
                    "#{pg_bin_dir}/pg_isready",
                    '-h', master_node['addr'],
                    '-p', master_node['port'],
                    '-t', 5,
                    '-U', REPMGR_USER,
                    '-d', REPMGR_USER,
                )
                
                warning('> register witness')
                begin
                    sudo('-H', '-u', user,
                         "#{pg_bin_dir}/pg_ctl", '-s', '-D', "#{data_dir}", 'stop'
                    )
                rescue
                end

                FileUtils.rm_rf data_dir
                
                # workaround for repmgr issues
                def_postgres_run_dir = "/run/postgresql"
                FileUtils.mkdir_p(def_postgres_run_dir, :mode => 0755)
                FileUtils.chown(user, user, def_postgres_run_dir)
                
                sudo('-H', '-u', user,
                    "#{root_dir}/bin/cfdb_repmgr",
                    '-h', master_node['addr'],
                    '-p', master_node['port'],
                    '-U', REPMGR_USER,
                    '-d', REPMGR_USER,
                    '-R', user.sub(/_arb$/, ''),
                    '-D', data_dir,
                    '-f', repmgr_file,
                     '--force',
                    'witness', 'create'
                )
                
                sudo('-H', '-u', user,
                     "#{pg_bin_dir}/pg_ctl", '-s', '-D', "#{data_dir}", 'stop'
                )
                
                FileUtils.rm_rf(def_postgres_run_dir)
                
                cf_system.atomicWrite(active_version_file, version)
                
                warning("> starting #{service_name}")
                systemctl('start', "#{service_name}.service")
                
                wait_sock(service_name, sock_file)
                
                warning("> starting #{repmgr_service_name}")
                systemctl('start', "#{repmgr_service_name}.service")
                
            rescue => e
                warning("Failed to setup witness: #{e}")
                warning("Master server needs to be re-provisioned after this host facts are known. Then run again")
                
                systemctl('stop', "#{service_name}.service")
                systemctl('stop', "#{repmgr_service_name}.service")
            end
            
        # No data: slave
        elsif is_cluster and is_secondary
            begin
                warning("> stopping #{service_name}")
                systemctl('stop', "#{service_name}.service")
                
                warning("> testing master connection #{master_node['addr']}")
                
                sudo('-H', '-u', user,
                    "#{pg_bin_dir}/pg_isready",
                    '-h', master_node['addr'],
                    '-p', master_node['port'],
                    '-t', 5,
                    '-U', REPMGR_USER,
                    '-d', REPMGR_USER,
                )
                
                warning('> cloning standby')
                FileUtils.touch(unclean_state_file)
                
                sudo('-H', '-u', user,
                    "#{root_dir}/bin/cfdb_repmgr",
                    '-h', master_node['addr'],
                    '-p', master_node['port'],
                    '-U', REPMGR_USER,
                    '-d', REPMGR_USER,
                    '-R', user,
                    '-D', data_dir,
                    '--ignore-external-config-files',
                    'standby', 'clone'
                )
                
                warning("> starting #{service_name}")
                systemctl('start', "#{service_name}.service")
                
                wait_sock(service_name, sock_file)
                
                sudo('-H', '-u', user,
                    "#{root_dir}/bin/cfdb_repmgr",
                    '-f', repmgr_file,
                     '--force',
                    'standby', 'register'
                )
                
                warning("> starting #{repmgr_service_name}")
                systemctl('start', "#{repmgr_service_name}.service")
                
                cf_system.atomicWrite(active_version_file, version)
                FileUtils.rm_f(unclean_state_file)
            rescue => e
                warning("Failed to clone/setup standby: #{e}")
                warning("Master server needs to be re-provisioned after this host facts are known. Then run again")
            end
            
        # No data: master
        else
            warning('> running initdb')
            FileUtils.touch(unclean_state_file)
            #--

            sudo('-u', user,
                 "#{pg_bin_dir}/initdb",
                 '--locale', cfdb_settings.fetch('locale', 'en_US.UTF-8'),
                 '--pwfile', pgpass_file,
                 '-D', data_dir)
            
            if File.exists?(active_version_file)
                warning('> migrating old data')
                old_version = File.read(active_version_file).strip()
                old_data = "#{root_data_dir}/#{old_version}"
                old_pg_bin_dir = "/usr/lib/postgresql/#{old_version}/bin"

                begin
                    sudo('-u', user,
                        "#{old_pg_bin_dir}/pg_ctl",
                        '-D', old_data,
                        'stop')
                rescue
                end
                
                warning("> stopping #{service_name}")
                systemctl('stop', "#{service_name}.service")

                sudo('-u', user, '/bin/sh', '-c',
                    "cd /tmp && #{pg_bin_dir}/pg_upgrade " +
                        "-d #{old_data} -D #{data_dir} " +
                        "-b #{old_pg_bin_dir} -B #{pg_bin_dir}")
                FileUtils.mv(old_data, "#{old_data}.bak")
            end
            
            if is_cluster and !is_secondary
                warning('> running repmgr configuration')
                
                warning("> starting #{service_name}")
                systemctl('start', "#{service_name}.service")
                
                wait_sock(service_name, sock_file)
                
                sudo('-H', '-u', user,
                     "#{root_dir}/bin/cfdb_psql", '-c',
                     "CREATE USER #{REPMGR_USER} SUPERUSER PASSWORD '#{root_pass}';")
                
                sudo('-H', '-u', user,
                     "#{root_dir}/bin/cfdb_psql", '-c',
                     "CREATE DATABASE #{REPMGR_USER} WITH OWNER = #{REPMGR_USER};")
                
                sudo('-H', '-u', user,
                     "#{root_dir}/bin/cfdb_psql", '-c',
                     "ALTER USER #{REPMGR_USER} SET search_path TO repmgr_#{cluster}, \"$user\", public;")
                
                sudo('-H', '-u', user,
                     "#{root_dir}/bin/cfdb_repmgr",
                     '-f', repmgr_file,
                     'master', 'register'
                )
                
                warning("> starting #{repmgr_service_name}")
                systemctl('start', "#{repmgr_service_name}.service")
            end
            
            cf_system.atomicWrite(active_version_file, version)
            #--
            FileUtils.rm_f(unclean_state_file)
            
            warning("> starting #{service_name}")
            systemctl('start', "#{service_name}.service")
            
            wait_sock(service_name, sock_file)
        end
        
        #---
        backup_init_stamp = "#{backup_wal_dir}/.init"
        if !is_arbitrator and !File.exists?(backup_init_stamp) and File.exists? data_dir
            sudo('-H', '-u', user, '/usr/bin/pg_backup_ctl',
                 '-h', run_dir,
                 '-p', port,
                 '-U', user,
                 '-A', backup_dir, 'setup')
            FileUtils.touch(backup_init_stamp)
        end
    end
    
    def atomicWritePG(file, settings, opts={})
        content = []
        settings.each do |k, v|
            if v.is_a? String
                v = v.gsub("'", "''")
                content << "#{k} = '#{v}'"
            else
                content << "#{k} = #{v}"
            end
        end
        
        content = content.join("\n") + "\n"
        
        self.cf_system.atomicWrite(file, content, opts)
    end
    
    def atomicWriteRepMgr(file, settings, opts={})
        content = []
        settings.each do |k, v|
            if v.is_a? String
                v = v.gsub("'", "''")
                content << "#{k}='#{v}'"
            else
                content << "#{k}=#{v}"
            end
        end
        
        content = content.join("\n") + "\n"
        
        self.cf_system.atomicWrite(file, content, opts)
    end
end