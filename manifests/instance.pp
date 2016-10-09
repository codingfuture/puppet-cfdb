
define cfdb::instance (
    $type,
    $is_cluster = false,
    $is_secondary = false,
    $is_bootstrap = false,
    $is_arbitrator = false,
    
    $memory_weight = 100,
    $memory_max = undef,
    $cpu_weight = 100,
    $io_weight = 100,
    $target_size = 'auto',
    
    $settings_tune = {},
    $databases = undef,
    
    $iface = $cfdb::iface,
    $port = undef,
    
    $backup = $cfdb::backup,
    $backup_tune = {},
    
    $ssh_key_type = 'ed25519',
    $ssh_key_bits = 2048, # for rsa
) {
    include stdlib
    include cfnetwork
    include cfsystem
    include cfdb
    
    include "cfdb::${type}"
    if $is_arbitrator {
        include "cfdb::${type}::arbitratorpkg"
    } else {
        include "cfdb::${type}::serverpkg"
    }
    
    #---
    $backup_support = !$is_arbitrator
    $is_cluster_by_fact = $is_cluster or $is_secondary or $is_arbitrator
    
    if ($is_cluster or $is_secondary) and !getvar("cfdb::${type}::is_cluster") {
        # that's mostly specific to MySQL
        fail("cfdb::${type}::is_cluster must be set to true, if cluster is expected")
    }
    
    if $backup_support {
        include cfdb::backup
    }
    
    #---
    case $type {
        'postgresql': {
            $ssh_access = $is_cluster_by_fact
        }
        default: {
            $ssh_access = false
        }
    }
    
    if $ssh_access {
        include cfauth
        $groups = 'ssh_access'
    } else {
        $groups = undef
    }
    
    
    #---
    $cluster = $title
    if $is_arbitrator {
        $service_name = "cf${type}-${cluster}-arb"
        $user = "${type}_${cluster}_arb"
    } else {
        $service_name = "cf${type}-${cluster}"
        $user = "${type}_${cluster}"
    }
    $root_dir = "${cfdb::root_dir}/${user}"
    $backup_dir = "${cfdb::backup::root_dir}/${user}"
    
    if $iface == 'any' {
        $listen = undef
    } elsif defined(Cfnetwork::Iface[$iface]) {
        $iface_addr = pick_default(getparam(Cfnetwork::Iface[$iface], 'address'), undef)
        
        if $iface_addr and is_string($iface_addr) {
            $listen = $iface_addr.split('/')[0]
        } else {
            $listen = undef
        }
    } else {
        $listen = undef
    }
    
    #---
    group { $user:
        ensure => present,
    }
    
    user { $user:
        ensure         => present,
        gid            => $user,
        home           => $root_dir,
        system         => true,
        shell          => '/bin/bash',
        groups         => $groups,
        purge_ssh_keys => true,
        require        => Group[$user],
    }
    
    #---
    $user_dirs = [
        $root_dir,
        "${root_dir}/bin",
        "${root_dir}/conf",
        "${root_dir}/var",
        "${root_dir}/tmp",
    ]
    file { $user_dirs:
        ensure => directory,
        owner  => $user,
        group  => $user,
        mode   => '0750',
    } ->
    cfsystem::puppetpki{ $user: }
    
    #---
    if $memory_max {
        $def_memory_max = $memory_max
    } elsif $is_arbitrator {
        $def_memory_max = 128
    } else {
        $def_memory_max = undef
    }
    
    if $is_arbitrator {
        $def_memory_min = 16
    } else {
        $def_memory_min = 128
    }
    
    $memory_mame = "cfdb-${cluster}"
    cfsystem_memory_weight { $memory_mame:
        ensure => present,
        weight => $memory_weight,
        min_mb => $def_memory_min,
        max_mb => $def_memory_max,
    }

    #---
    if $is_cluster_by_fact {
        if !$port {
            fail('Cluster requires excplicit port')
        }
        
        $cluster_facts_all = cf_query_facts(
            "cfdb.${cluster}.present=true",
            ['cfdb']
        )
        
        if empty($cluster_facts_all) {
            $cluster_addr = []
        } else {
            $secure_cluster = try_get_value($settings_tune, 'cfdb/secure_cluster')
            
            $cluster_addr = (keys($cluster_facts_all).sort().map |$host| {
                $cfdb_facts = $cluster_facts_all[$host]
                $cluster_fact = $cfdb_facts['cfdb'][$cluster]
                
                if $type != $cluster_fact['type'] {
                    fail("Type of ${cluster} on ${host} mismatch ${type}: ${cluster_fact}")
                }
                
                if $secure_cluster {
                    # we need hostname for commonName checking
                    $peer_addr = $host
                } else {
                    $peer_addr = pick($cluster_fact['host'], $host)
                }
                $peer_port = $cluster_fact['port']
                
                if $host == $::trusted['certname'] {
                    undef
                } else {
                    if !$peer_addr or !$peer_port {
                        fail("Invalid host/port for ${host}: ${cluster_fact}")
                    }
                    
                    $host_under = regsubst($host, '\.', '_', 'G')
                    
                    if $ssh_access {
                        cfnetwork::client_port { "${iface}:cfssh:cfdb_${cluster}_${host_under}":
                            dst  => $peer_addr,
                            user => $user,
                        }
                        cfnetwork::service_port { "${iface}:cfssh:cfdb_${cluster}_${host_under}":
                            src => $peer_addr,
                        }
                        
                        pick($cluster_fact['ssh_keys'], {}).each |$kn, $kv| {
                            ssh_authorized_key { "${user}:${kn}@${host_under}":
                                user    => $user,
                                type    => $kv['type'],
                                key     => $kv['key'],
                                require => User[$user],
                            }
                        }
                    }
                    
                    if $type == 'mysql' {
                        $galera_port = cfdb_derived_port($peer_port, 'galera')
                        $sst_port = cfdb_derived_port($peer_port, 'galera_sst')
                        $ist_port = cfdb_derived_port($peer_port, 'galera_ist')
                    
                        cfnetwork::describe_service { "cfdb_${cluster}_peer_${host_under}":
                            server => "tcp/${peer_port}",
                        }
                        cfnetwork::describe_service { "cfdb_${cluster}_galera_${host_under}":
                            server => [
                                "tcp/${galera_port}",
                                "udp/${galera_port}"
                            ],
                        }
                        cfnetwork::describe_service { "cfdb_${cluster}_sst_${host_under}":
                            server => "tcp/${sst_port}",
                        }
                        cfnetwork::describe_service { "cfdb_${cluster}_ist_${host_under}":
                            server => "tcp/${ist_port}",
                        }
                        
                        cfnetwork::client_port { "${iface}:cfdb_${cluster}_peer_${host_under}":
                            dst  => $peer_addr,
                            user => $user,
                        }
                        cfnetwork::client_port { "${iface}:cfdb_${cluster}_galera_${host_under}":
                            dst  => $peer_addr,
                            user => $user,
                        }
                        cfnetwork::client_port { "${iface}:cfdb_${cluster}_sst_${host_under}":
                            dst  => $peer_addr,
                            user => $user,
                        }
                        cfnetwork::client_port { "${iface}:cfdb_${cluster}_ist_${host_under}":
                            dst  => $peer_addr,
                            user => $user,
                        }
                    } elsif $type == 'postgresql' {
                        cfnetwork::describe_service { "cfdb_${cluster}_peer_${host_under}":
                            server => "tcp/${peer_port}",
                        }
                        
                        cfnetwork::client_port { "${iface}:cfdb_${cluster}_peer_${host_under}":
                            dst  => $peer_addr,
                            user => $user,
                        }
                    }
                    
                    $ret = {
                        addr          => $peer_addr,
                        port          => $peer_port,
                        is_secondary  => $cluster_fact['is_secondary'],
                        is_arbitrator => $cluster_fact['is_arbitrator'],
                    }
                    $ret
                }
            }).filter |$v| { $v != undef }
        }
        
        $peer_addr_list = $cluster_addr.map |$v| {
            $v['addr']
        }
        
        if $type == 'mysql' {
            $galera_port = cfdb_derived_port($port, 'galera')
            $sst_port = cfdb_derived_port($port, 'galera_sst')
            $ist_port = cfdb_derived_port($port, 'galera_ist')
            
            cfnetwork::describe_service { "cfdb_${cluster}_peer":
                server => "tcp/${port}",
            }
            cfnetwork::describe_service { "cfdb_${cluster}_galera":
                server => [
                    "tcp/${galera_port}",
                    "udp/${galera_port}"
                ],
            }
            cfnetwork::describe_service { "cfdb_${cluster}_sst":
                server => "tcp/${sst_port}",
            }
            cfnetwork::describe_service { "cfdb_${cluster}_ist":
                server => "tcp/${ist_port}",
            }
            
            if size($peer_addr_list) > 0 {
                cfnetwork::service_port { "${iface}:cfdb_${cluster}_peer":
                    src => $peer_addr_list,
                }
                cfnetwork::service_port { "${iface}:cfdb_${cluster}_galera":
                    src => $peer_addr_list,
                }
                cfnetwork::service_port { "${iface}:cfdb_${cluster}_sst":
                    src => $peer_addr_list,
                }
                cfnetwork::service_port { "${iface}:cfdb_${cluster}_ist":
                    src => $peer_addr_list,
                }
            }
        } elsif $type == 'postgresql' {
            cfnetwork::describe_service { "cfdb_${cluster}_peer":
                server => "tcp/${port}",
            }
         
            if size($peer_addr_list) > 0 {
                cfnetwork::service_port { "${iface}:cfdb_${cluster}_peer":
                    src => $peer_addr_list,
                }
            }
            
            # a workaround for ignorant PostgreSQL devs
            #---
            cfnetwork::service_port { "local:alludp:${cluster}-stats": }
            cfnetwork::client_port { "local:alludp:${cluster}-stats":
                user => $user,
            }
            #---
        }
        
        if $ssh_access {
            $ssh_dir = "${root_dir}/.ssh"
            $ssh_idkey = "${ssh_dir}/id_${ssh_key_type}"
            
            exec { "cfdb_genkey@${user}":
                command => "/usr/bin/ssh-keygen -q -t ${ssh_key_type} -b ${ssh_key_bits} -P '' -f ${ssh_idkey}",
                creates => $ssh_idkey,
                user    => $user,
                group   => $user,
                require => User[$user],
            } ->
            file { "${ssh_dir}/config":
                owner   => $user,
                group   => $user,
                content => [
                    'StrictHostKeyChecking no',
                    "IdentityFile ${ssh_idkey}",
                ].join("\n")
            }
        }
        
        $shared_secret = keys($cluster_facts_all).reduce('') |$memo, $host| {
            $cfdb_facts = $cluster_facts_all[$host]
            $cluster_fact = $cfdb_facts['cfdb'][$cluster]
            
            if !$cluster_fact['is_secondary'] and $cluster_fact['shared_secret'] {
                $cluster_fact['shared_secret']
            } else {
                $memo
            }
        }
    } else {
        $cluster_addr = undef
        $shared_secret = ''
    }
    
    #---
    $access = cf_query_facts("cfdbaccess.${cluster}.present=true", ['cfdbaccess'])
    $access_list = $access.reduce({}) |$memo, $val| {
        $host = $val[0]
        $cluster_info = $val[1]['cfdbaccess'][$cluster]
        $cluster_info['roles'].reduce($memo) |$imemo, $ival| {
            $role = $ival[0]
            $role_info = $ival[1]['client'].map |$v| {
                {
                    host    => pick($v['host'], $host).split('/')[0],
                    maxconn => $v['max_connections'],
                }
            }
            
            if $imemo[$role] {
                merge($imemo, {
                    "${role}" => $imemo[$role] + $role_info
                })
            } else {
                merge($imemo, {
                    "${role}" => $role_info
                })
            }
        }
    }
    
    #---
    $fact_port = cf_genport($cluster, $port)
    $is_first_node = $cluster_addr and (size($cluster_addr) == 0)

    cfdb_instance { $cluster:
        ensure        => present,
        type          => $type,
        cluster       => $cluster,
        user          => $user,
        is_cluster    => $is_cluster_by_fact,
        is_secondary  => $is_secondary or $is_arbitrator,
        is_bootstrap  => ($is_bootstrap or $is_first_node) and !$is_arbitrator,
        is_arbitrator => $is_arbitrator,
        
        memory_weight => $memory_weight,
        cpu_weight    => $cpu_weight,
        io_weight     => $io_weight,
        target_size   => $target_size,
        
        root_dir      => $root_dir,
        backup_dir    => $backup_dir,
        
        settings_tune => merge(
            $settings_tune,
            {
                cfdb => merge(
                    {
                        'listen'        => $listen,
                        'port'          => $fact_port,
                        'shared_secret' => $shared_secret,
                    },
                    pick($settings_tune['cfdb'], {})
                )
            }
        ),
        service_name  => $service_name,
        version       => getvar("cfdb::${type}::actual_version"),
        cluster_addr  => $cluster_addr ? {
            undef   => undef,
            default => cf_stable_sort($cluster_addr),
        },
        access_list   => $access_list ? {
            undef   => undef,
            default => cf_stable_sort($access_list),
        },
        
        require       => [
            User[$user],
            File[$user_dirs],
            Class["cfdb::${type}::serverpkg"],
            Cfsystem_memory_weight[$memory_mame],
            Cfsystem::Puppetpki[$user],
        ],
    }
    
    # service { $service_name:
    #         enable  => true,
    #         require => [
    #             Cfdb_instance[$cluster],
    #             Cfsystem_flush_config['commit'],
    #         ]
    #     }
    
    #---
    if !$is_secondary and !$is_arbitrator {
        $healthcheck = $cfdb::healthcheck
        cfdb::database { "${cluster}/${healthcheck}":
            cluster  => $cluster,
            database => $healthcheck,
        }
    }
    
    #---
    if $databases {
        if $is_secondary or $is_arbitrator {
            fail("It's not allowed to defined databases on secondary server")
        }
        
        if is_array($databases) {
            $databases.each |$db| {
                create_resources(
                    cfdb::database,
                    {
                        "${cluster}/${db}" => {
                            cluster  => $cluster,
                            database => $db,
                        }
                    },
                    {
                        require => [
                            Cfdb_instance[$cluster],
                        ]
                    }
                )
            }
        } elsif is_hash($databases) {
            $databases.each |$db, $cfg| {
                create_resources(
                    cfdb::database,
                    {
                        "${cluster}/${db}" => pick_default($cfg, {})
                    },
                    {
                        cluster  => $cluster,
                        database => $db,
                        require => [
                            Cfdb_instance[$cluster],
                        ]
                    }
                )
            }
        } else {
            fail('$databases must be an array or hash')
        }
    }
    
    # Open firewall for clients and/or add optional haproxy endpoint
    #---
    if $access {
        if $fact_port and ($fact_port != '') {
            $sec_port = cfdb_derived_port($fact_port, 'secure')
            
            ensure_resource('cfnetwork::describe_service', "cfdb_${cluster}", {
                server => "tcp/${fact_port}",
            })
            ensure_resource('cfnetwork::describe_service', "cfdbsec_${cluster}", {
                server => "tcp/${sec_port}",
            })
            
            cfnetwork::service_port { "local:cfdb_${cluster}": }
            cfnetwork::client_port { "local:cfdb_${cluster}":
                user => $user,
            }
            
            $required_endpoints = cf_query_resources(
                false,
                ['extract', ['certname', 'parameters'],
                    ['and',
                        ['=', 'type', 'Cfdb::Require_endpoint'],
                        ['=', ['parameter', 'host'], $::trusted['certname']],
                        ['=', ['parameter', 'cluster'], $cluster],
                    ],
                ],
                false,
            )

            $allowed_hosts = unique($required_endpoints.reduce([]) |$memo, $v| {
                $params = $v['parameters']

                if $params['secure'] {
                    $memo
                } else {
                    $memo + [$params['source']]
                }
            })
            
            $sec_allowed_hosts = $required_endpoints.reduce({}) |$memo, $v| {
                $params = $v['parameters']

                if $params['secure'] {
                    $source = $params['source']
                    merge($memo, {
                        $source => $params['maxconn'] + pick($memo[$source], 0)
                    })
                } else {
                    $memo
                }
            }
            
            if size($allowed_hosts) > 0 {
                cfnetwork::service_port { "${iface}:cfdb_${cluster}":
                    src => $allowed_hosts.sort(),
                }
            }
            if size($sec_allowed_hosts) > 0 {
                cfnetwork::service_port { "${iface}:cfdbsec_${cluster}":
                    src => keys($sec_allowed_hosts).sort(),
                }
                $maxconn = $sec_allowed_hosts.reduce(0) |$memo, $kv| {
                    $memo + $kv[1]
                }
                include cfdb::haproxy
                cfdb_haproxy_endpoint { $cluster:
                    ensure          => present,
                    listen          => $listen,
                    sec_port        => $sec_port,
                    service_name    => $service_name,
                    type            => $type,
                    cluster         => $cluster,
                    max_connections => $maxconn,
                }
            }
        }
    }
    
    
    # setup backup & misc.
    #---
    if $backup_support {
        $backup_script = "${cfdb::bin_dir}/cfdb_${cluster}_backup"
        $restore_script = "${cfdb::bin_dir}/cfdb_${cluster}_restore"
        $backup_script_auto ="${backup_script}_auto"
        
        file { $backup_dir:
            ensure => directory,
            owner  => $user,
            group  => $user,
            mode   => '0750',
        }
        
        file { $backup_script:
            mode    => '0755',
            content => epp("cfdb/cfdb_backup_${type}.epp", merge({
                backup_dir => $backup_dir,
                root_dir   => $root_dir,
                user       => $user,
            }, $backup_tune)),
            require => File[$backup_dir],
            notify  => Cfdb_instance[$cluster],
        } ->
        file { "${root_dir}/bin/cfdb_backup":
            ensure => link,
            target => $backup_script,
        }
        
        file { $restore_script:
            mode    => '0755',
            content => epp("cfdb/cfdb_restore_${type}.epp", {
                backup_dir   => $backup_dir,
                root_dir     => $root_dir,
                user         => $user,
                service_name => $service_name,
            }),
            require => File[$backup_dir],
            notify  => Cfdb_instance[$cluster],
        } ->
        file { "${root_dir}/bin/cfdb_restore":
            ensure => link,
            target => $restore_script,
        }
        
        if $backup == false {
            file { $backup_script_auto:
                ensure => absent,
            }
        } else {
            file { $backup_script_auto:
                ensure  => link,
                target  => $backup_script,
                require => File[$backup_script],
            }
        }
    }
    
    # exta tools
    #---
    case $type {
        'mysql': {
            if !$is_arbitrator {
                $mysql_script = "${cfdb::bin_dir}/cfdb_${cluster}_mysql"
                file { $mysql_script:
                    mode    => '0755',
                    content => epp('cfdb/cfdb_mysql.epp', {
                        user => $user,
                    }),
                    notify  => Cfdb_instance[$cluster],
                } ->
                file { "${root_dir}/bin/cfdb_mysql":
                    ensure => link,
                    target => $mysql_script,
                }
                
                $sysbench_script = "${cfdb::bin_dir}/cfdb_${cluster}_sysbench"
                file { $sysbench_script:
                    mode    => '0755',
                    content => epp('cfdb/cfdb_sysbench.epp', {
                        user => $user,
                    }),
                } ->
                file { "${root_dir}/bin/cfdb_sysbench":
                    ensure => link,
                    target => $sysbench_script,
                }
            }
        }
        'postgresql': {
            if !$is_arbitrator {
                $psql_script = "${cfdb::bin_dir}/cfdb_${cluster}_psql"
                file { $psql_script:
                    mode    => '0755',
                    content => epp('cfdb/cfdb_psql.epp', {
                        user         => $user,
                        service_name => $service_name,
                    }),
                    notify  => Cfdb_instance[$cluster],
                } ->
                file { "${root_dir}/bin/cfdb_psql":
                    ensure => link,
                    target => $psql_script,
                }
            }
            
            if $is_cluster_by_fact {
                $repmgr_script = "${cfdb::bin_dir}/cfdb_${cluster}_repmgr"
                file { $repmgr_script:
                    mode    => '0755',
                    content => epp('cfdb/cfdb_repmgr.epp', {
                        root_dir     => $root_dir,
                        user         => $user,
                        service_name => $service_name,
                    }),
                    notify  => Cfdb_instance[$cluster],
                } ->
                file { "${root_dir}/bin/cfdb_repmgr":
                    ensure => link,
                    target => $repmgr_script,
                }
            }
        }
        default: {
            fail("${type} - not supported type")
        }
    }
}