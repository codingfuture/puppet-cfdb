#
# Copyright 2016-2017 (c) Andrey Galkin
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
    $tune_bufsize = pick(try_get_value($settings_tune, 'global/tune.bufsize'), 16384)

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

    # connect only to DB nodes in same DC
    $cf_location = $::facts['cf_location']
    $cluster_facts_try = cf_query_facts(
        "cfdb.${cluster}.present=true and cfdb.${cluster}.is_arbitrator=false and cf_location='${cf_location}'",
        ['cfdb', 'cf_location']
    )

    if size($cluster_facts_try) > 0 {
        $cluster_facts_all = $cluster_facts_try
    } else {
        # fallback to connect to any possible DC
        $cluster_facts_all = cf_query_facts(
            "cfdb.${cluster}.present=true and cfdb.${cluster}.is_arbitrator=false",
            ['cfdb', 'cf_location']
        )
    }

    if empty($cluster_facts_all) {
        $cluster_addr = []
    } else {
        $cluster_addr = (keys($cluster_facts_all).sort.map |$host| {
            $cfdb_facts = $cluster_facts_all[$host]
            $cluster_fact = $cfdb_facts['cfdb'][$cluster]
            $is_local = ($::trusted['certname'] == $host)

            if $type != $cluster_fact['type'] {
                fail("Type of ${cluster} on ${host} mismatch ${type}: ${cluster_fact}")
            }

            # it does not really work with database protocols :(
            if $is_local {
                $secure_host = false
            } elsif $force_secure {
                $secure_host = true
            } elsif $force_insecure {
                $secure_host = false
            } else {
                $secure_host = ($cf_location != $cfdb_facts['cf_location'])
            }

            $addr = $is_local ? {
                true    => '127.0.0.1',
                default => pick($cluster_fact['host'], $host),
            }

            $port = $secure_host ? {
                true    => cfdb_derived_port($cluster_fact['port'], 'secure'),
                default => $cluster_fact['port'],
            }

            if !$addr or !$port {
                fail("Invalid host/port for ${host}: ${cluster_fact}")
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
                backup => $cluster_fact['is_secondary'],
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
        require         => Cfdb_haproxy[$cfdb::haproxy::service_name],
    }

    #---
    $healthcheck = $cfdb::healthcheck
    $healthcheck_access_title = "${cluster}/${healthcheck}"

    if !defined(Cfdb_access[$healthcheck_access_title]) {
        $health_check_facts = cf_query_facts(
            "cfdb.${cluster}.is_secondary=false and cfdb.${cluster}.roles.${healthcheck}.present=true",
            ['cfdb']
        )
        if size($health_check_facts) > 0 {
            $healthcheck_password = values($health_check_facts)[0]['cfdb'][$cluster]['roles'][$healthcheck]['password']
        } else {
            # temporary
            $healthcheck_password = $healthcheck
        }

        cfdb_access{ $healthcheck_access_title:
            ensure          => present,
            cluster         => $cluster,
            role            => $healthcheck,
            local_user      => undef,
            max_connections => 2,
            client_host     => $client_host,
            config_info     => {},
        }


        #---
        file { "${cfdb::haproxy::bin_dir}/check_${cluster}":
            ensure  => present,
            owner   => $cfdb::haproxy::user,
            group   => $cfdb::haproxy::user,
            mode    => '0750',
            content => epp("cfdb/health_check_${type}", {
                service_name => $cfdb::haproxy::service_name,
                role         => $healthcheck,
                password     => $healthcheck_password,
                database     => $healthcheck,
            }),
        }
    }
}
