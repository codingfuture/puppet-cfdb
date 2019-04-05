#
# Copyright 2016-2019 (c) Andrey Galkin
#


define cfdb::instance (
    Enum[
        'mysql',
        'postgresql',
        'elasticsearch',
        'mongodb',
        'redis'
    ]
        $type,
    Boolean
        $is_cluster = false,
    Boolean
        $is_secondary = false,
    Boolean
        $is_bootstrap = false,
    Boolean
        $is_arbitrator = false,

    Integer[1]
        $memory_weight = 100,
    Optional[Integer[1]]
        $memory_min = undef,
    Optional[Integer[1]]
        $memory_max = undef,
    Cfsystem::CpuWeight
        $cpu_weight = 100,
    Cfsystem::IoWeight
        $io_weight = 100,

    Variant[Enum['auto'], Integer[1]]
        $target_size = 'auto',

    Hash[String[1], Any]
        $settings_tune = {},
    Optional[Variant[Array[String[1]], Hash]]
        $databases = undef,

    Cfnetwork::Bindface
        $iface = $cfdb::iface,
    Cfnetwork::Bindface
        $cluster_face = $cfdb::cluster_face,
    Optional[Cfnetwork::Port]
        $port = undef,

    Boolean
        $backup = $cfdb::backup,
    Hash
        $backup_tune = {},

    Cfsystem::Keytype
        $ssh_key_type = 'ed25519',
    Cfsystem::Rsabits
        $ssh_key_bits = 2048, # for rsa

    Hash[String[1], Hash]
        $scheduled_actions = {},
) {
    include stdlib
    include cfnetwork
    include cfsystem
    include cfdb
    include cfdb::backup

    $cluster = $title

    include "cfdb::${type}"
    if $is_arbitrator {
        include "cfdb::${type}::arbitratorpkg"

        Class["cfdb::${type}::arbitratorpkg"]
        -> Cfdb_instance[$cluster]
    } else {
        include "cfdb::${type}::serverpkg"
        include "cfdb::${type}::clientpkg"

        Class["cfdb::${type}::serverpkg"]
        -> Class["cfdb::${type}::clientpkg"]
        -> Cfdb_instance[$cluster]
    }

    #---
    $backup_support = !$is_arbitrator
    $is_cluster_by_fact = $is_cluster or $is_secondary or $is_arbitrator
    $is_primary_node = !$is_secondary and !$is_arbitrator

    if ($is_cluster or $is_secondary) and !getvar("cfdb::${type}::is_cluster") {
        # that's mostly specific to MySQL
        fail("cfdb::${type}::is_cluster must be set to true, if cluster is expected")
    }

    #---
    case $type {
        'postgresql', 'mysql': {
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
    if $is_arbitrator {
        $service_name = "cf${type}-${cluster}-arb"
        $user = "${type}_${cluster}_arb"
    } else {
        $service_name = "cf${type}-${cluster}"
        $user = "${type}_${cluster}"
    }
    $root_dir = "${cfdb::root_dir}/${user}"
    $backup_dir = "${cfdb::backup::root_dir}/${user}"

    # Listen parameter auto-detection
    # We need to listen on all ifaces, if clients and cluster mismatch
    #---
    if $iface == 'any' or
        ($is_cluster_by_fact and $iface != $cluster_face)
    {
        $listen = undef
    } else {
        $listen = cfnetwork::bind_address($iface)
    }

    # Listen for cluster-only comms
    #---
    $cluster_listen = $is_cluster_by_fact ? {
        true    => cfnetwork::bind_address($cluster_face),
        default => undef,
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
    }
    -> cfsystem::puppetpki{ $user: }

    #---
    if $memory_max {
        $def_memory_max = $memory_max
    } elsif $is_arbitrator {
        $def_memory_max = getvar("cfdb::${type}::defaults::max_arb_memory")
    } else {
        $def_memory_max = getvar("cfdb::${type}::defaults::max_memory")
    }

    if $memory_min {
        $def_memory_min = $memory_min
    } elsif $is_arbitrator {
        $def_memory_min = getvar("cfdb::${type}::defaults::min_arb_memory")
    } else {
        $def_memory_min = getvar("cfdb::${type}::defaults::min_memory")
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

        $secure_cluster = $settings_tune.dig('cfdb', 'secure_cluster')

        if $secure_cluster and $cluster_face != 'main' {
            # TODO: custom PKI to support extra hostnames
            fail('Unfortunately, secure_cluster supports only "main" cluster_face')
        }

        $cluster_instances = cfsystem::query([
            'from', 'resources', ['extract', [ 'certname', 'parameters' ],
                ['and',
                    ['=', 'type', 'Cfdb_instance'],
                    ['=', 'title', $cluster],
                ],
        ]])

        if empty($cluster_instances) {
            $cluster_addr = []
        } else {
            $cluster_addr_raw = $cluster_instances.map |$host_info| {
                $host = $host_info['certname']
                $params = $host_info['parameters']
                $cfdb = $params['settings_tune']['cfdb']

                if $type != $params['type'] {
                    fail("Type of ${cluster} on ${host} mismatch ${type}: ${host_info}")
                }

                $peer_addr = $secure_cluster ? {
                    true => pick(
                        $cfdb['cluster_addr'] ? {
                            'undef' => undef,
                            ''      => undef,
                            default => $cfdb['cluster_addr']
                        },
                        $host
                    ),
                    default => pick(
                        $cfdb['cluster_listen'] ? {
                            'undef' => undef,
                            ''      => undef,
                            default => $cfdb['cluster_listen']
                        },
                        $cfdb['listen'] ? {
                            'undef' => undef,
                            '' => undef,
                            default => $cfdb['listen']
                        },
                        $host
                    ),
                }
                $peer_port = $cfdb['port']

                if $peer_port != $port {
                    if !$is_primary_node and !$params['is_secondary'] {
                        fail("Port ${port} mismatch primary ${peer_port} for ${cluster}")
                    }
                    undef
                } elsif $host == $::trusted['certname'] {
                    undef
                } else {
                    if !$peer_addr or !$peer_port {
                        fail("Invalid host/port ${peer_addr}/${peer_port} for ${host}: ${host_info}")
                    }

                    $ret = {
                        addr          => $peer_addr,
                        port          => $peer_port,
                        is_secondary  => $params['is_secondary'],
                        is_arbitrator => $params['is_arbitrator'],
                    }
                    $ret
                }
            }
            $cluster_addr = cfsystem::stable_sort(delete_undef_values($cluster_addr_raw))
        }

        $peer_addr_list = $cluster_addr.map |$v| {
            $v['addr']
        }

        $cluster_ipset = "cfdb_${cluster}"
        cfnetwork::ipset { $cluster_ipset:
            type => 'ip',
            addr => cfsystem::stable_sort($peer_addr_list),
        }

        create_resources("cfdb::${type}::clusterports", {
            $title => {
                iface     => cfnetwork::fw_face($cluster_face),
                cluster   => $cluster,
                user      => $user,
                ipset     => $cluster_ipset,
                peer_port => $port,
            }
        })

        if $ssh_access {
            cfsystem::clusterssh { "cfdb:${cluster}":
                namespace  => 'cfdb',
                cluster    => $cluster,
                user       => $user,
                is_primary => $is_primary_node,
                key_type   => $ssh_key_type,
                key_bits   => $ssh_key_bits,
                peer_ipset => $cluster_ipset
            }
        }

        $secret_title = "cfdb/${cluster}"

        if $is_primary_node {
            $shared_secret_tune = $settings_tune.dig('cfdb', 'shared_secret')
        } else {
            $shared_secret_tune = $cluster_instances.reduce(undef) |$memo, $host_info| {
                $host = $host_info['certname']
                $params = $host_info['parameters']
                $shared_secret_param = $params['settings_tune'].dig('cfdb', 'shared_secret')

                if !$params['is_secondary'] and $shared_secret_param {
                    $shared_secret_param
                } else {
                    $memo
                }
            }
        }
    } else {
        $cluster_addr = []

        $secret_title = "cfdb/${cluster}"
        $shared_secret_tune = $settings_tune.dig('cfdb', 'shared_secret')
    }

    $shared_secret = cfsystem::gen_pass($secret_title, 24, $shared_secret_tune)

    #---
    $access = cfsystem::query([
        'from', 'resources', ['extract', [ 'certname', 'parameters' ],
            ['and',
                ['=', 'type', 'Cfdb_access'],
                ['=', ['parameter', 'cluster'], $cluster],
            ],
    ]])

    $access_list = $access.reduce({}) |$memo, $val| {
        $certname = $val['certname']
        $params = $val['parameters']

        $maxconn = pick($params['max_connections'], $cfdb::max_connections_default)
        $client_host = pick($params['client_host'], $certname).split('/')[0]
        $role = $params['role']

        $role_info = [{
            host        => $certname,
            client_host => $client_host,
            maxconn     => $maxconn,
        }]

        if $memo[$role] {
            merge($memo, {
                "${role}" => $memo[$role] + $role_info
            })
        } else {
            merge($memo, {
                "${role}" => $role_info
            })
        }
    }

    #---
    $fact_port = cfsystem::gen_port($cluster, $port)

    #---
    $is_first_node = $is_cluster_by_fact and (size($cluster_addr) == 0)
    $version = getvar("cfdb::${type}::actual_version")

    $act_settings_tune = merge(
        $settings_tune,
        {
            cfdb => merge(
                {
                    'listen'         => $listen,
                    'cluster_listen' => $cluster_listen,
                },
                pick($settings_tune['cfdb'], {}),
                {
                    'port'          => $fact_port,
                    'shared_secret' => $shared_secret,
                },
            )
        }
    )

    cfdb_instance { $cluster:
        ensure        => present,
        type          => $type,
        cluster       => $cluster,
        user          => $user,
        is_cluster    => $is_cluster_by_fact,
        is_secondary  => !$is_primary_node,
        is_bootstrap  => ($is_bootstrap or $is_first_node) and !$is_arbitrator,
        is_arbitrator => $is_arbitrator,

        memory_weight => $memory_weight,
        cpu_weight    => $cpu_weight,
        io_weight     => $io_weight,
        target_size   => $target_size,

        root_dir      => $root_dir,
        backup_dir    => $backup_dir,

        settings_tune => $act_settings_tune,
        service_name  => $service_name,
        version       => $version,
        cluster_addr  => $cluster_addr,
        access_list   => cfsystem::stable_sort($access_list),
        location      => $cfdb::location,

        require       => [
            User[$user],
            File[$user_dirs],
            Cfsystem_memory_weight[$memory_mame],
            Cfsystem::Puppetpki[$user],
            Anchor['cfnetwork:firewall'],
        ],
    }

    # service { $service_name:
    #         enable   => true,
    #         provider => 'systemd',
    #         require  => [
    #             Cfdb_instance[$cluster],
    #             Cfsystem_flush_config['commit'],
    #         ]
    #     }

    #---
    if $is_primary_node {
        $healthcheck = $cfdb::healthcheck
        cfdb::database { "${cluster}/${healthcheck}":
            cluster  => $cluster,
            database => $healthcheck,
        }
    }

    #---
    if $is_primary_node and getvar("cfdb::${type}::is_unidb") {
        cfdb::database { "${cluster}/${cluster}":
            cluster  => $cluster,
            database => $cluster,
            require  => Cfdb_instance[$cluster],
        }
    } elsif $databases {
        if !$is_primary_node {
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
            $sec_port = cfdb::derived_port($fact_port, 'secure')

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

            $required_endpoints = cfsystem::query([
                'from', 'resources', ['extract', ['parameters'],
                    ['and',
                        ['=', 'type', 'Cfdb::Require_endpoint'],
                        ['=', ['parameter', 'host'], $::trusted['certname']],
                        ['=', ['parameter', 'cluster'], $cluster],
                    ],
            ]])

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

            $fw_face = cfnetwork::fw_face($iface)

            if size($allowed_hosts) > 0 {
                $ipset_clients = "cfdb_${cluster}_clients"

                cfnetwork::ipset { $ipset_clients:
                    addr => $allowed_hosts.sort(),
                }
                cfnetwork::service_port { "${fw_face}:cfdb_${cluster}":
                    dst => $listen,
                    src => "ipset:${ipset_clients}",
                }

                if $type == 'elasticsearch' {
                    $peer_port = cfdb::derived_port($fact_port, 'elasticsearch')

                    ensure_resource('cfnetwork::describe_service', "cfdb_${cluster}_peer", {
                        server => "tcp/${peer_port}",
                    })
                    cfnetwork::service_port { "${fw_face}:cfdb_${cluster}_peer:clients":
                        dst => $listen,
                        src => "ipset:${ipset_clients}",
                    }
                }
            }

            if size($sec_allowed_hosts) > 0 {
                $ipset_secclients = "cfdb_${cluster}_secclients"

                cfnetwork::ipset { $ipset_secclients:
                    addr => keys($sec_allowed_hosts).sort(),
                }
                cfnetwork::service_port { "${fw_face}:cfdbsec_${cluster}":
                    dst => $listen,
                    src => "ipset:${ipset_secclients}",
                }

                $maxconn = $sec_allowed_hosts.reduce(0) |$memo, $kv| {
                    $memo + $kv[1]
                }

                include cfdb::haproxy
                # in case of TCP
                cfnetwork::client_port { "local:cfdb_${cluster}:cfdbhaproxy":
                    dst  => $listen,
                    user => $cfdb::haproxy::user,
                }
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
        }

        # Remove insecure artifacts
        file { "${root_dir}/bin/cfdb_backup":
            ensure => absent,
        }
        file { "${root_dir}/bin/cfdb_restore":
            ensure => absent,
        }

        # Cleanup legacy
        file { $backup_script_auto:
            ensure => absent,
        }

        if $backup {
            cfbackup::path { $backup_dir:
                namespace => 'cfdb',
                id        => $user,
                type      => 'periodic_dump',
                prepare   => $backup_script,
            }
        }
    }

    # extra tools
    #---
    create_resources("cfdb::${type}::instancebin", { $title => {
        cluster       => $cluster,
        user          => $user,
        root_dir      => $root_dir,
        service_name  => $service_name,
        version       => $version,
        is_cluster    => $is_cluster_by_fact,
        is_arbitrator => $is_arbitrator,
        is_primary    => $is_primary_node,
        settings_tune => $act_settings_tune,
        sched_actions => $scheduled_actions,
    }})

    # metrics
    #---
    cfsystem::metric { $cluster:
        type => 'cfdb',
        info => {
            type    => $type,
            cluster => $cluster,
            role    => $cfdb::healthcheck,
        }
    }
}
