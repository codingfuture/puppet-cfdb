
# Done this way due to some weird behavior in tests also ignoring $LOAD_PATH
require File.expand_path( '../../../../puppet_x/cf_system/provider_base', __FILE__ )

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
    
    MYSQL = '/usr/bin/mysql'
    MYSQLD = '/usr/sbin/mysqld'
    MYSQLADMIN = '/usr/bin/mysqladmin'
    MYSQL_INSTALL_DB = '/usr/bin/mysql_install_db'
    MYSQL_UPGRADE = '/usr/bin/mysql_upgrade'

    def self.get_config_index
        'cfdb_instance'
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
    
    def self.create_service(conf, service_ini, service_env)
        db_type = conf[:type]
        service_name = conf[:service_name]
        service_file = "/etc/systemd/system/#{service_name}.service"
        env_file = "/etc/default/#{service_name}.conf"
        user = conf[:user]
        
        cpu_shares = (1024 * conf[:cpu_weight].to_i / 100).to_i
        
        mem_limit = cf_system.getMemory(conf[:cluster_name])
        
        io_weight = (1000 * conf[:io_weight].to_i / 100).to_i
        io_weight = fit_range(1, 1000, io_weight)
        
        #---
        content_env = {
            'CFDB_ROOT_DIR' => conf[:root_dir],
        }
        
        content_env.merge! service_env
       
        cf_system().atomicWriteEnv(env_file, content_env, {:mode => 0644})
        
        #---
        content_ini = {
            'Unit' => {
                'Description' => "CFDB instance: #{service_name}",
                'After' => [
                    'syslog.target',
                    'network.target',
                ],
            },
            'Service' => {
                'EnvironmentFile' => env_file,
                'Type' => 'simple',
                'Restart' => 'always',
                'RestartSec' => 5,
                'User' => user,
                'Group' => user,
                'CPUShares' => cpu_shares,
                'BlockIOWeight' => io_weight,
                'MemoryLimit' => "#{mem_limit}M",
                'LimitMEMLOCK' => "#{mem_limit}M",
                'LimitNOFILE' => 100000,
                'UMask' => '0027',
                'WorkingDirectory' => conf[:root_dir],
                'RuntimeDirectory' => service_name,
            },
            'Install' => {
                'WantedBy' => 'multi-user.target',
            },
        }
        
        content_ini['Service'].merge! service_ini
        
        reload = cf_system().atomicWriteIni(service_file, content_ini, {:mode => 0644})
       
        if reload
            systemctl('daemon-reload')
        end
    end
    
    def self.disk_size(dir)
        ret = df('-BM', '--output=size', dir)
        ret = ret.split("\n")
        ret[1].strip().to_i
    end
    
    BINLOG_RESERVE = 10
    
    #==================================
    def self.create_mysql(conf)
        debug('create_mysql')
        cf_system = self.cf_system()
        
        root_dir = conf[:root_dir]
        conf_dir = "#{root_dir}/conf"
        data_dir = "#{root_dir}/data"
        tmp_dir = "#{root_dir}/tmp"
        
        cluster_name = conf[:cluster_name]
        service_name = conf[:service_name]
        server_id = 1 # TODO
        type = conf[:type]
        conf_file = "#{conf_dir}/mysql.cnf"
        client_conf_file = "#{root_dir}/.my.cnf"
        init_file = "#{conf_dir}/setup.sql"
        
        run_dir = "/run/#{service_name}"
        sock_file = "#{run_dir}/service.sock"
        pid_file = "#{run_dir}/service.pid"

        user = conf[:user]
        settings_tune = conf[:settings_tune]
        cfdb_settings = settings_tune.fetch('cfdb', {})
        mysqld_tune = settings_tune.fetch('mysqld', {})
        optimize_ssd = cfdb_settings.fetch('optimize_ssd', false)
        
        root_pass = cf_system.genSecret(cluster_name)
        port = cf_system.genPort(cluster_name)
        
        data_exists = File.exists?(data_dir)
        
        
        # TODO: auto-choose
        #---
        bind_address = '127.0.0.1'
        #---
        
        # TODO: calculate based on user access list x limit
        #---
        max_connections = 1024
        #---

        # Auto-tune to have enough open table cache        
        #---
        inodes_min = 1024
        inodex_max = 10240
        
        if data_exists
            inodes_used = du('--inodes', '--summarize', data_dir).to_i
            inodes_used = inodes_used / inodes_min * inodes_min
        else
            inodes_used = 1024
        end
           
        inodes_used = fit_range(inodes_min, inodex_max, inodes_used)
        table_definition_cache = mysqld_tune.fetch('table_definition_cache', inodes_used)
        table_open_cache = mysqld_tune.fetch('table_open_cache', inodes_used)
        #---
        
        # with safe limit
        open_file_limit = 3 * (max_connections + table_definition_cache + table_open_cache)
        
        
        # Complex tuning based on target DB size and available RAM
        #==================================================
        
        # target database size
        target_size = conf[:target_size]
        
        if target_size == 'auto'
            # we ignore other possible instances
            target_size = disk_size(root_dir)
        end
        
        max_binlog_files = 20
        mb = 1024 * 1024
        gb = mb * 1024
        binlog_reserve = target_size * BINLOG_RESERVE / 100
        
        if binlog_reserve < (max_binlog_files * gb)
            max_binlog_size = 256 * mb
        else
            max_binlog_size = gb
        end
        
        avail_mem = cf_system.getMemory(cluster_name) * mb
        
        #
        default_chunk_size = 2 * gb
        max_pools = 64

        innodb_buffer_pool_size = avail_mem * 80 / 100
        innodb_buffer_pool_chunk_size = default_chunk_size
        
        if innodb_buffer_pool_size > (max_pools * innodb_buffer_pool_chunk_size)
            round_pool = gb
            innodb_buffer_pool_chunk_size = innodb_buffer_pool_size / max_pools / round_pool * round_pool
            innodb_buffer_pool_size = innodb_buffer_pool_chunk_size * max_pools
            innodb_buffer_pool_instances = max_pools
            innodb_sort_buffer_size = 64 * mb
        elsif innodb_buffer_pool_size > innodb_buffer_pool_chunk_size
            round_pool = 128 * mb
            innodb_buffer_pool_instances = innodb_buffer_pool_size / innodb_buffer_pool_chunk_size
            innodb_buffer_pool_instances = fit_range(1, max_pools, innodb_buffer_pool_instances)
            
            if innodb_buffer_pool_instances > 1
                innodb_buffer_pool_chunk_size = innodb_buffer_pool_chunk_size / round_pool * round_pool
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
        elsif (target_size > (10 * gb)) and (avail_mem > (gb))
            innodb_log_file_size = '128M'
            innodb_log_buffer_size = '32M'
        else
            innodb_log_file_size = '16M'
            innodb_log_buffer_size = '8M'
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
                'innodb_buffer_pool_chunk_size' => innodb_buffer_pool_chunk_size,
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
                'log_bin' => "#{data_dir}/#{cluster_name}#{server_id}-bin",
                'log_slave_updates' => 'TRUE',
                'max_binlog_size' => max_binlog_size,
                'max_binlog_files' => max_binlog_files,
                'max_connections' => max_connections,
                'server_id' => server_id,
                'table_definition_cache' => table_definition_cache,
                'table_open_cache' => table_open_cache,
                'transaction_isolation' => 'READ-COMMITTED',
            },
            'client' => client_settings,
        }
        
        mysqld_settings = conf_settings['mysqld']
        
        # tunes
        settings_tune.each do |k, v|
            next if k == 'cfdb'
            mysqld_settings[k] = {} if not mysqld_settings.has_key? k
            mysqld_settings[k].merge! v
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
            'skip_name_resolve' => 'ON',
            'socket' => sock_file,
            'tmpdir' => tmp_dir,
            'user' => user,
        }
        
        mysqld_settings.merge! forced_settings
        
        cf_system.atomicWriteIni(conf_file, conf_settings, { :user => user})
        
        # Prepare service file
        #---
        service_ini = {
            'LimitNOFILE' => open_file_limit * 2,
            'ExecStart' => "/usr/sbin/mysqld --defaults-file=#{conf_dir}/mysql.cnf $MYSQLD_OPTS",
        }
        service_env = {
            'MYSQLD_OPTS' => '',
        }
        create_service(conf, service_ini, service_env)
        
        # Prepare data dir
        #---
        if data_exists
            upgrade_file = "#{conf_dir}/upgrade_stamp"
            upgrade_ver = sudo('-u', user, MYSQL_UPGRADE, '--version')
            
            if !File.exists?(upgrade_file) or (upgrade_ver != File.read(upgrade_file))
                warning('> running mysql upgrade')
                systemctl('start', "#{service_name}.service")
                sudo('-u', user, MYSQL_UPGRADE, '--force')
                File.open(upgrade_file, 'w+', 0600) do |f|
                    f.write(upgrade_ver)
                end
                FileUtils.chown(user, user, upgrade_file)
            end
        else
            have_initialize = sudo(MYSQLD, '--verbose', '--help')
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
                    "--datadir=#{data_dir}",
                    "--mysqld-file=" + MYSQLD)
                systemctl('start', "#{service_name}.service")
            end
            
            if not File.exists? data_dir
                raise Puppet::DevError, "Failed to initialize #{data_dir}"
            end
        end
        
        #TODO: copy data from master, if slave
    end
    
    #==================================
    def self.create_postgresql(conf)
        debug('create_postgresql')
    end
end
