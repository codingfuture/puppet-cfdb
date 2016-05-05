
# Done this way due to some weird behavior in tests also ignoring $LOAD_PATH
require File.expand_path( '../../../../puppet_x/cf_system/provider_base', __FILE__ )

Puppet::Type.type(:cfdb_instance).provide(
    :cfdb,
    :parent => PuppetX::CfSystem::ProviderBase
) do
    desc "Provider for cfdb_instance"
    
    commands :sudo => '/usr/bin/sudo'
    commands :systemctl => '/bin/systemctl'
    commands :df => '/bin/df'
    
    MYSQL = '/usr/bin/mysql'
    MYSQLD = '/usr/sbin/mysqld'
    MYSQLADMIN = '/usr/bin/mysqladmin'
    MYSQL_INSTALL_DB = '/usr/bin/mysql_install_db'

    def self.get_config_index
        'cfdb_instance'
    end

    def self.get_generator_version
        cf_system().makeVersion(__FILE__)
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
    
    def self.create_service(conf, service_ini)
        service_name = conf[:service_name]
        service_file = "/etc/systemd/system/#{service_name}.service"
        user = conf[:user]
        
        cpu_shares = (1024 * conf[:cpu_weight].to_i / 100).to_i
        mem_limit = cf_system.getMemory(conf[:cluster_name])
        io_weight = (1000 * conf[:io_weight].to_i / 100).to_i
        io_weight = fit_range(1, 1000, io_weight)
        
        content_ini = {
            'Unit' => {
                'Description' => "DB instance: #{service_name}",
                'After' => [
                    'syslog.target',
                    'network.target',
                ],
            },
            'Service' => {
                'Type' => 'Simple',
                'User' => user,
                'Group' => user,
                'CPUShares' => (1024 * conf[:cpu_weight].to_i / 100).to_i,
                'MemoryLimit' => "#{mem_limit}M",
                'LimitMEMLOCK' => "#{mem_limit}M",
                'BlockIOWeight' => io_weight,
                'UMask' => '0027',
                'WorkingDirectory' => conf[:root_dir],
            },
            'Install' => {
                'WantedBy' => 'multi-user.target',
            },
        }
        
        content_ini['Service'].merge! service_ini
        
        cf_system().atomicWriteIni(service_file, content_ini)
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
        data_dir = "#{root_dir}/data"
        tmp_dir = "#{root_dir}/tmp"
        
        cluster_name = conf[:cluster_name]
        service_name = conf[:service_name]
        server_id = 1 # TODO
        type = conf[:type]
        conf_file = "#{root_dir}/conf/mysql.cnf"
        client_conf_file = "#{root_dir}/.my.cnf"
        init_file = "#{root_dir}/setup.sql"
        sock_file = "/run/#{service_name}.sock"
        pid_file = "/run/#{service_name}.pid"

        user = conf[:user]
        settings_tune = conf[:settings_tune]
        cfdb_settings = settings_tune.fetch('cfdb', {})
        optimize_ssd = cfdb_settings.fetch('optimize_ssd', false)
        
        # TODO: auto-choose
        bind_address = '127.0.0.1'
        open_file_limit = 100000
        
        
        root_pass = cf_system.genSecret(cluster_name)
        port = cf_system.genPort(cluster_name)
        
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
        
        avail_mem = cf_system.getMemory(cluster_name)
        
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
            "SET PASSWORD = PASSWORD('#{root_pass}');",
            'FLUSH PRIVILEGES;',
        ]
        cf_system.atomicWrite(init_file, setup_sql.join('\n'), { :user => user})
        
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
                'innodb_file_per_table:' => 'ON',
                'innodb_flush_log_at_trx_commit' => 2,
                'innodb_io_capacity' => innodb_io_capacity,
                'innodb_io_capacity_max' => innodb_io_capacity_max,
                'innodb_log_buffer_size' => innodb_log_buffer_size,
                'innodb_log_file_size' => innodb_log_file_size,
                'innodb_sort_buffer_size' => innodb_sort_buffer_size,
                'innodb_strict_mode' => 'ON',
                'innodb_thread_concurrency' => innodb_thread_concurrency,
                'log_bin' => 'ON',
                'log_bin_basename' => "#{cluster_name}#{server_id}-bin",
                'log_slave_updates' => 'TRUE',
                'max_binlog_size' => max_binlog_size,
                'max_binlog_files' => max_binlog_files,
                'server_id' => server_id,
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
            'default_time_zone' => 'UTC',
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
        create_service(conf, {
            'LimitNOFILE' => open_file_limit * 2,
        })
        
        # Prepare data dir
        #---
        if not File.exists?(data_dir)
            # TODO: only for <5.7
            sudo('-u', user, MYSQL_INSTALL_DB,
                "--defaults-file=#{conf_file}",
                "--datadir=#{data_dir}",
                "--mysqld-file=" + MYSQLD)
            systemctl('start', "#{service_name}.service")
        else
            # TODO: conditional upgrade DB
        end
    end
    
    #==================================
    def self.create_postgresql(conf)
        debug('create_postgresql')
    end
end
