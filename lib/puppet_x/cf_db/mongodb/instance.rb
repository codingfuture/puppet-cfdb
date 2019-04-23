#
# Copyright 2019 (c) Andrey Galkin
#


module PuppetX::CfDb::MongoDB::Instance
    include PuppetX::CfDb::MongoDB

    def call_mongo(conf, cmd, auth=true, ignore=false)
        user = conf[:user]
        root_dir = conf[:root_dir]

        # NOTE: there is a known Mongo Shell issues that --eval is executed BEFORE .mongorc.js
        tmp_exec_file = "#{root_dir}/tmp/shellcmd.js"

        cf_system.atomicWrite(tmp_exec_file, cmd, {:user => user, :silent => true})

        begin
            args = []

            if auth
                args << "#{root_dir}/.mongorc.js"
            end

            args << tmp_exec_file

            res = sudo('-H', '-u', user, MONGO,
                '--host', "#{root_dir}/server.sock",
                'admin',
                '--quiet', '--norc',
                *args)
            FileUtils.rm_f tmp_exec_file
            return res.strip().split("\n").drop(2)
        rescue => e
            if !ignore
                warning("> CMD: #{cmd}")
                warning("> Error: #{e}")
            end
            raise
        end
    end

    def wait_mongo_ready(conf, sock_file, timeout=60)
        user = conf[:user]
        service_name = conf[:service_name]

        wait_sock(service_name, sock_file, timeout)
        
        for i in 1..timeout
            begin
                call_mongo(conf, 'db.runCommand( { ping: 1 } )', [], true)
                return true
            rescue => e
                warning("Waiting #{service_name} to become ready (#{i})!")
                sleep 3
            end
        end

        fail("Failed to wait for #{service_name} to become ready")
    end
    
    def create_mongodb(conf)
        debug('create_mongodb')
        cf_system = self.cf_system()
        
        root_dir = conf[:root_dir]
        conf_dir = "#{root_dir}/conf"
        data_dir = "#{root_dir}/data"
        tmp_dir = "#{root_dir}/tmp"
        pki_dir = "#{root_dir}/pki/puppet"
        bin_dir = "#{root_dir}/bin"
        backup_dir = conf[:backup_dir]
        
        cluster = conf[:cluster]
        service_name = conf[:service_name]
        version = conf[:version]
        is_secondary = conf[:is_secondary]
        is_cluster = conf[:is_cluster]
        is_arbitrator = conf[:is_arbitrator]
        cluster_addr = conf[:cluster_addr]
        access_list = conf[:access_list]
        type = conf[:type]
        conf_file = "#{conf_dir}/mongod.conf"
        
        run_dir = "/run/#{service_name}"
        restart_required_file = "#{conf_dir}/restart_required"

        user = conf[:user]
        settings_tune = conf[:settings_tune]
        cfdb_settings = settings_tune.fetch('cfdb', {})
        mongo_tune = settings_tune.fetch('mongodb', {})
        
        data_exists = File.exists?(data_dir)
        
        ver_parts = version.split('.')
        fqdn = Facter['fqdn'].value()

        #---
        root_name = 'root'
        root_pass = cfdb_settings['shared_secret']
        
        if root_pass.nil? or root_pass.empty?
            fail("Shared secret must be generated in DSL")
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
                
                if host != fqdn or (client_host != 'localhost' and client_host != '127.0.0.1')
                    have_external_conn = true
                end
            end
        end
        
        max_connections_roundto = cfdb_settings.fetch('max_connections_roundto', 100).to_i
        max_connections = round_to(max_connections_roundto, max_connections)
        #---
        
        port = cfdb_settings['port']
        fail('Missing port') if port.nil?

        sock_file = "#{run_dir}/mongodb-#{port}.sock"
        secure_cluster = cfdb_settings.fetch('secure_cluster', false)
        
        #---
        if have_external_conn or is_cluster
            bind_address = cfdb_settings['listen'] || '0.0.0.0'
            cluster_bind_address = cfdb_settings['cluster_listen'] || '0.0.0.0'

            if secure_cluster
                bind_address = fqdn
            end
        else
            bind_address = '127.0.0.1'
            cluster_bind_address = bind_address
        end

        #---
        local_sock_file = "#{root_dir}/server.sock"
        FileUtils.ln_sf(sock_file, local_sock_file)
        
        #---
        mongorc = [
            # It seems mongo has issues if not using --host
            #"conn = Mongo('#{sock_file}');",
            #"db = conn.getDB('admin');",
            "db.auth('#{root_name}', '#{root_pass}');",
        ]

        if is_arbitrator
            mongorc = ''
        end
        
        cf_system.atomicWrite("#{root_dir}/.mongorc.js", mongorc, {:user => user, :show_diff => false})

        mongoenv = [
            "DB_HOST=#{bind_address}",
            "DB_PORT=#{port}",
            "ROOT_USER=#{root_name}",
            "ROOT_PASS=#{root_pass}",
        ]
        cf_system.atomicWrite("#{root_dir}/.mongorc.sh", mongoenv, {:user => user, :show_diff => false})

        #---
        avail_mem = get_memory(cluster)
        cache_coef = cfdb_settings.fetch('cache_percent', 50).to_f / 100.0

        #---

        
        # defaults
        conf_settings = {
            'systemLog.quiet' => true,
            'systemLog.verbosity' => 0,
            #'systemLog.destination' => 'syslog',
            'systemLog.timeStampFormat' => 'iso8601-utc',

            #'cloud.monitoring.free.state' => 'off',

            'net.wireObjectCheck' => true,
            'net.serviceExecutor' => 'adaptive',

            'storage.journal.commitIntervalMs' => 500,
            'storage.engine' => 'wiredTiger',
            'storage.wiredTiger.engineConfig.cacheSizeGB' => (avail_mem * cache_coef / 1024),
            'storage.wiredTiger.engineConfig.journalCompressor' => 'snappy',
            'storage.wiredTiger.engineConfig.directoryForIndexes' => true,
            'storage.wiredTiger.collectionConfig.blockCompressor' => 'zlib',
        }

        #---
        single_pem_file = "#{pki_dir}/single.pem"
        single_pem = File.read("#{pki_dir}/local.key") + File.read("#{pki_dir}/local.crt")
        cf_system.atomicWrite(single_pem_file, single_pem, {:user => user, :show_diff => false})

        #---
        plain_key_file = "#{conf_dir}/shared.key"
        cf_system.atomicWrite(plain_key_file, Base64.encode64(root_pass),
                              {:user => user, :show_diff => false})

        # forced
        add_root_user = !data_exists && !is_secondary && !is_arbitrator
        forced_settings = {
            'processManagement.fork' => false,

            'net.port' => port,
            'net.bindIp' => bind_address,
            'net.bindIpAll' => false,
            'net.maxIncomingConnections' => max_connections,
            'net.ipv6' => false,

            'net.unixDomainSocket.enabled' => true,
            'net.unixDomainSocket.pathPrefix' => run_dir,
            'net.unixDomainSocket.filePermissions' => '0777',

            'net.ssl.mode' => secure_cluster ? 'preferSSL' : 'allowSSL',
            'net.ssl.PEMKeyFile' => single_pem_file,
            'net.ssl.CAFile' => "#{pki_dir}/ca.crt",
            'net.ssl.CRLFile' => "#{pki_dir}/crl.crt",
            'net.ssl.allowConnectionsWithoutCertificates' => false,
            'net.ssl.allowInvalidCertificates' => false,

            'security.authorization' => add_root_user ? 'disabled' : 'enabled',
            'security.keyFile' => plain_key_file,
            'security.clusterAuthMode' => 'sendKeyFile',

            'storage.dbPath' => data_dir,
            'storage.journal.enabled' => true,
            'storage.directoryPerDB' => true,
        }

        if is_cluster
            forced_settings.merge!({
                'replication.replSetName' => cluster,
                'replication.enableMajorityReadConcern' => true,
            })
        end

        conf_settings.merge! mongo_tune
        conf_settings.merge! forced_settings

        # write
        config_file_changed = cf_system.atomicWrite(conf_file, conf_settings.to_yaml, { :user => user })

        # Prepare service file
        #---
        service_ini = {
            '# Package Version' => PuppetX::CfSystem::Util.get_package_version(
                                        "percona-server-mongodb-#{version.sub('.','')}"),

            'LimitNOFILE' => 'infinity',
            'LimitNPROC' => 'infinity',
            'LimitAS' => 'infinity',
            'LimitFSIZE' => 'infinity',
            'TimeoutStopSec' => 0,
            'KillSignal' => 'SIGTERM',
            'KillMode' => 'process',
            'SendSIGKILL' => 'no',
            'ExecStart' => "#{MONGOD} -f #{conf_file}",
            'ExecStartPost' => "/bin/rm -f #{restart_required_file}",
            'OOMScoreAdjust' => -200,
        }
        service_env = {}
        service_changed = create_service(conf, service_ini, service_env)
        
        config_changed = config_file_changed || service_changed

        if !data_exists
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

        if add_root_user
            warning('> initializing')
            wait_mongo_ready(conf, sock_file)

            call_mongo(conf, 'rs.initiate()', false)
            
            # Get some time to become master
            sleep 3

            # Mongo has quite weird internal security checks...
            cmd = [
                "db.createUser({user:'#{root_name}',pwd:'#{root_pass}',roles:['root']});",
                # Just do not ask what WTF is here..
                "db.auth('#{root_name}','#{root_pass}');",
                'db.createRole(
                    { role: "superadmin",
                      privileges: [ { resource: { anyResource: true }, actions: [ "anyAction" ] } ],
                      roles: []
                    });',
                "db.grantRolesToUser('#{root_name}', ['superadmin'])",
            ]

            call_mongo(conf, cmd, false)

            conf_settings['security.authorization'] = 'enabled'
            cf_system.atomicWrite(conf_file, conf_settings.to_yaml, { :user => user })

            warning('> restarting')
            FileUtils.touch(restart_required_file)
            FileUtils.chown(user, user, restart_required_file)
            systemctl('restart', "#{service_name}.service")
        end

        if is_cluster
            wait_sock(service_name, sock_file)

            wait_mongo_ready(conf, sock_file)

            ismaster = call_mongo(conf, 'print(rs.isMaster().ismaster)')[0]

            if ismaster != 'true'
                if !is_arbitrator && !is_secondary
                    # Show the warning only 
                    warning("!!! The current node is not PRIMARY for #{cluster} !!!")
                    warning("Unable to configure, use 'rs.stepDown()' on PRIMARY.")
                end
            elsif is_arbitrator or is_secondary
                warning("!!! Trying to step down from Primary for #{cluster} !!!")
                begin
                    call_mongo(conf, 'rs.stepDown()')

                    # give some time
                    sleep 15
                rescue => e
                    warning("FAILED: #{e}")
                end

                ismaster = call_mongo(conf, 'print(rs.isMaster().ismaster)')[0]
            end

            if ismaster == 'true'
                members = call_mongo(
                        conf,
                        'for (let m of rs.config().members) { print(m.host); }')

                cluster_addr.each { |m|
                    maddr = "#{m['addr']}:#{m['port']}"
                    next if members.include? maddr
                    warning("> missing #{maddr} in #{members}")

                    if m['is_arbitrator']
                        warning("> adding #{maddr} abitrator to #{cluster}")
                        rs_add = "rs.addArb('#{maddr}')"
                    else
                        warning("> adding #{maddr} node to #{cluster}")
                        rs_add = "rs.add('#{maddr}')"
                    end

                    begin
                        call_mongo(conf, rs_add)
                    rescue => e
                        warning("FAILED: #{e}")
                    end
                }
            end
        end
        
        return check_cluster_mongodb(conf)
    end

    def check_cluster_mongodb(conf)
        return true if !conf[:is_cluster]

        root_dir = conf[:root_dir]
        cluster = conf[:cluster]
        bin_dir = "#{root_dir}/bin/cfdb_curl"

        begin
            fact_cluster_size = call_mongo(
                conf,
                'let i = 0; for (let m of rs.status().members) { if (m.health === 1) { ++i; } }; print(i)',
                ['--quiet'])[0].to_i

            cluster_size = conf[:cluster_addr].size + 1

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
