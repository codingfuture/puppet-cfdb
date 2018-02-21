#
# Copyright 2018 (c) Andrey Galkin
#

module PuppetX::CfDb::Elasticsearch::Instance
    include PuppetX::CfDb::Elasticsearch
    
    def create_elasticsearch(conf)
        debug('create_elasticsearch')
        cf_system = self.cf_system()
        
        root_dir = conf[:root_dir]
        conf_dir = "#{root_dir}/conf"
        data_dir = "#{root_dir}/data"
        tmp_dir = "#{root_dir}/tmp"
        bin_dir = "#{root_dir}/bin"
        
        cluster = conf[:cluster]
        service_name = conf[:service_name]
        version = conf[:version]
        is_secondary = conf[:is_secondary]
        is_cluster = conf[:is_cluster]
        is_arbitrator = conf[:is_arbitrator]
        cluster_addr = conf[:cluster_addr]
        access_list = conf[:access_list]
        type = conf[:type]
        conf_file = "#{conf_dir}/elasticsearch.yml"
        log4j_file = "#{conf_dir}/log4j2.properties"
        
        run_dir = "/run/#{service_name}"
        restart_required_file = "#{conf_dir}/restart_required"
        upgrade_file = "#{conf_dir}/upgrade_stamp"

        user = conf[:user]
        settings_tune = conf[:settings_tune]
        cfdb_settings = settings_tune.fetch('cfdb', {})
        esearch_tune = settings_tune.fetch('elasticsearch', {})
        
        data_exists = File.exists?(data_dir)
        
        fqdn = Facter['fqdn'].value()
        
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
            bind_address = cfdb_settings['listen'] || '0.0.0.0'
            cluster_bind_address = cfdb_settings['cluster_listen'] || '0.0.0.0'
        else
            bind_address = '127.0.0.1'
        end
        
        port = cfdb_settings['port']
        cluster_port = port.to_i + CLUSTER_PORT_OFFSET
        fail('Missing port') if port.nil?

        #---
        cfdb_curl = [
            '#!/bin/dash',
            'p=$1',
            'shift',
            "/usr/bin/curl --silent \"http://#{bind_address}:#{port}$p\" \"$@\""
        ]
        cf_system.atomicWrite("#{bin_dir}/cfdb_curl", cfdb_curl, { :user => user, :mode => 0750 })

        #---
        avail_mem = get_memory(cluster)
        heap_mem = (avail_mem / 2).to_i
        minimum_master_nodes = ( (cluster_addr.size + 1) / 2).to_i + 1

        #---

        
        # defaults
        conf_settings = {
            'cluster.routing.allocation.same_shard.host' => true,
            'http.max_content_length' => '8mb',
            'logger.deprecation.level' => 'warn',
        }

        if cluster_addr.size < 1
            conf_settings['discovery.type'] = 'single-node'
        end
        
        # forced
        forced_settings = {
            'cluster.name' => cluster,
            'node.name' => fqdn,
            'discovery.zen.ping.unicast.hosts' => cluster_addr.map { |v| v['addr'] },
            'discovery.zen.minimum_master_nodes' => minimum_master_nodes,
            'http.host' => bind_address,
            'http.port' => port,
            'network.host' => cluster_bind_address,
            'transport.tcp.port' => cluster_port,
            'path.data' => data_dir,
            'path.logs' => tmp_dir,
        }

        if is_arbitrator
            forced_settings.merge!({
                'node.master' => true,
                'node.data' => false,
                'node.ingest' => false,
                'search.remote.connect' => false,
            })
        end

        conf_settings.merge! esearch_tune
        conf_settings.merge! forced_settings

        # write
        config_file_changed = cf_system.atomicWrite(conf_file, conf_settings.to_yaml, { :user => user })
        
        # Prepare service file
        #---
        service_ini = {
            '# Package Version' => PuppetX::CfSystem::Util.get_package_version('elasticsearch'),
            'LimitNOFILE' => 'infinity',
            'LimitNPROC' => '4096',
            'LimitAS' => 'infinity',
            'LimitFSIZE' => 'infinity',
            'TimeoutStopSec' => 0,
            'KillSignal' => 'SIGTERM',
            'KillMode' => 'process',
            'SendSIGKILL' => 'no',
            'SuccessExitStatus' => '143',
            'ExecStart' => "#{ELASTICSEARCH}",
            'ExecStartPost' => "/bin/rm -f #{restart_required_file}",
            'OOMScoreAdjust' => -200,
        }
        service_env = {
            'ES_HOME' => '/usr/share/elasticsearch',
            'ES_PATH_CONF' => conf_dir,
            'ES_JAVA_OPTS' => "-Xms#{heap_mem}m -Xmx#{heap_mem}m",
        }
        service_changed = create_service(conf, service_ini, service_env)
        
        config_changed = config_file_changed || service_changed

        if !data_exists
            FileUtils.mkdir(data_dir, :mode => 0750)
            FileUtils.chown(user, user, data_dir)
            systemctl('start', "#{service_name}.service")
        elsif config_changed
            FileUtils.touch(restart_required_file)
            FileUtils.chown(user, user, restart_required_file)
        end

        return check_cluster_elasticsearch(conf)
    end

    def check_cluster_elasticsearch(conf)
        root_dir = conf[:root_dir]
        cluster = conf[:cluster]
        bin_dir = "#{root_dir}/bin/cfdb_curl"

        begin
            res = sudo('-H', '-u', conf[:user],
                "#{root_dir}/bin/cfdb_curl",
                "/_cluster/health?local",
                '--max-time', '3'
            )

            res = JSON.parse( res )
            cluster_size = conf[:cluster_addr].size + 1
            fact_cluster_size = res['number_of_nodes']

            if res['status'] != 'green'
                warning("> cluster #{cluster} status is #{res['status']}")
            end
            
            if fact_cluster_size != cluster_size
                warning("> cluster #{cluster} is incomplete #{fact_cluster_size}/#{cluster_size}")
            end
        rescue => e
            warning(e)
            #warning(e.backtrace)
            conf[:settings_tune]['need_setup'] = true
            false
        end
    end
end
