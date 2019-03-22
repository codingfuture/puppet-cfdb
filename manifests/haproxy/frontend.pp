#
# Copyright 2016-2019 (c) Andrey Galkin
#


define cfdb::haproxy::frontend(
    $type,
    $cluster,
    $access_user,
    $max_connections,
    $socket,
    $secure_mode,
    $distribute_load,
    $client_host,
    $use_unix_socket,
    $local_port,
) {
    assert_private()

    include cfnetwork
    include cfdb::haproxy
    include "cfdb::${type}::clientpkg"

    #---
    $settings_tune = $cfdb::haproxy::settings_tune
    $tune_bufsize = pick($settings_tune.dig('global', 'tune.bufsize'), 16384)

    # That's a guess so far. Need more precise calculation
    $mem_per_conn_kb = ceiling($tune_bufsize / 1024.0)
    $mem_per_secure_conn_kb = $mem_per_conn_kb * 2

    $force_secure = ($secure_mode == 'secure')
    $force_insecure = ($secure_mode == 'insecure')

    if $force_secure {
        $extra_mem_kb = ($mem_per_conn_kb + $mem_per_secure_conn_kb) * $max_connections
    } else {
        $extra_mem_kb = 2 * $mem_per_conn_kb * $max_connections
    }


    cfsystem_memory_weight { "${cfdb::haproxy::service_name}/${title}":
        ensure => present,
        weight => 0,
        min_mb => ceiling($extra_mem_kb / 1024.0),
    }

    #---
    $cluster_instances_try = cfsystem::query([
        'from', 'resources', ['extract', [ 'certname', 'parameters' ],
            ['and',
                ['=', 'type', 'Cfdb_instance'],
                ['=', 'title', $cluster],
                ['=', ['parameter', 'is_arbitrator'], false],
                ['=', ['parameter', 'location'], $cfdb::location],
            ],
    ]])

    if size($cluster_instances_try) > 0 {
        $cluster_instances = $cluster_instances_try
    } else {
        $cluster_instances = cfsystem::query([
            'from', 'resources', ['extract', [ 'certname', 'parameters' ],
                ['and',
                    ['=', 'type', 'Cfdb_instance'],
                    ['=', 'title', $cluster],
                    ['=', ['parameter', 'is_arbitrator'], false],
                ],
        ]])
    }


    if empty($cluster_instances) {
        $cluster_addr = []
    } else {
        $cluster_addr = cfsystem::stable_sort($cluster_instances.map |$cluster_info| {
            $host = $cluster_info['certname']
            $params = $cluster_info['parameters']

            $cfdb = $params['settings_tune']['cfdb']
            $is_local = ($::trusted['certname'] == $host)

            if $type != $params['type'] {
                fail("Type of ${cluster} on ${host} mismatch ${type}: ${cluster_info}")
            }

            # it does not really work with database protocols :(
            if $is_local {
                $secure_host = false
            } elsif $force_secure {
                $secure_host = true
            } elsif $force_insecure {
                $secure_host = false
            } else {
                $secure_host = (
                    ($cfdb::location != $params['location']) and
                    # for migration from older versions
                    pick($params['location'], '') != '' and
                    $cfdb::location != ''
                )
            }

            $addr = $is_local ? {
                true    => '127.0.0.1',
                default => pick(
                    $cfdb['listen'] ? {
                        'undef' => undef,
                        ''      => undef,
                        default => $cfdb['listen']
                    },
                    $host
                )
            }

            $port = $secure_host ? {
                true    => cfdb::derived_port($cfdb['port'], 'secure'),
                default => $cfdb['port'],
            }

            if !$addr or !$port {
                fail("Invalid host/port ${addr}/${port} for ${host}: ${cluster_info}")
            }

            $host_under = regsubst($host, '\.', '_', 'G')
            $fw_service = "cfdbha_${cluster}_${port}"
            $fw_port = $is_local ? {
                true => "local:${fw_service}:${host_under}",
                default => "any:${fw_service}:${host_under}",
            }

            ensure_resource('cfnetwork::describe_service', $fw_service, {
                server => "tcp/${port}",
            })

            ensure_resource('cfnetwork::client_port', $fw_port, {
                dst  => $addr,
                user => $cfdb::haproxy::user,
            })

            cfdb::require_endpoint{ "${title}:${host}":
                cluster => $cluster,
                host    => $host,
                source  => $::trusted['certname'],
                maxconn => $max_connections,
                secure  => $secure_host,
            }

            if $secure_host {
                $server_name = "${host_under}_TLS_${port}"
            } else {
                $server_name = "${host_under}_${port}"
            }

            $ret = {
                server => $server_name,
                host   => $host,
                addr   => $addr,
                port   => $port,
                backup => $params['is_secondary'],
                secure => $secure_host,
            }
            $ret
        })
    }

    #---
    cfdb_haproxy_frontend { $title:
        ensure          => present,
        type            => $type,
        cluster         => $cluster,
        access_user     => $access_user,
        max_connections => $max_connections,
        socket          => $socket,
        is_secure       => $force_secure,
        distribute_load => $distribute_load,
        cluster_addr    => $cluster_addr,
        use_unix_socket => $use_unix_socket,
        local_port      => $local_port,
        require         => [
            Cfdb_haproxy[$cfdb::haproxy::service_name],
            Anchor['cfnetwork:firewall'],
        ]
    }

    #---
    ensure_resource('cfdb::healthcheck', $cluster, {
        type        => $type,
        cluster     => $cluster,
        client_host => $client_host,
        add_haproxy => true,
    })
}
