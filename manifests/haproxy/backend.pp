
define cfdb::haproxy::backend(
    $type,
    $cluster,
    $role,
    $password,
    $access_user,
    $max_connections,
    $socket,
    $is_secure,
    $distribute_load,
) {
    assert_private()
    
    include cfnetwork
    include cfdb::haproxy
    
    #---
    $settings_tune = $cfdb::haproxy::settings_tune
    $tune_bufsize = pick(try_get_value($settings_tune, 'global/tune.bufsize'), 16384)
    
    # That's a guess so far. Need more precise calculation
    $mem_per_conn_kb = ceiling($tune_bufsize / 1024.0)
    $mem_per_secure_conn_kb = $mem_per_conn_kb * 2
    
    if $is_secure {
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
    if $is_secure {
        fail('Unfortunately, DB protocols do not support pure TLS tunnel.
        An advanced [client -> HAProxy -> internet -> Haproxy -> server] solution may be implemented later.
        ')
    }
    
    # connect only to DB nodes in same DC
    $cluster_facts_try = query_facts(
        "cfdb.${cluster}.present=true and cfdb.${cluster}.is_arbitrator=false and cf_location='${cf_location}'",
        ['cfdb', 'cf_location']
    )
    
    if size($cluster_facts_try) {
        $cluster_facts_all = $cluster_facts_try
    } else {
        # fallback to connect to any possible DC
        $cluster_facts_all = query_facts(
            "cfdb.${cluster}.present=true and cfdb.${cluster}.is_arbitrator=false",
            ['cfdb', 'cf_location']
        )
    }
    
    if empty($cluster_facts_all) {
        $cluster_addr = []
    } else {
        $cf_location = $::facts['cf_location']
        
        $cluster_addr = (keys($cluster_facts_all).sort.map |$host| {
            $cfdb_facts = $cluster_facts_all[$host]
            $cluster_fact = $cfdb_facts['cfdb'][$cluster]
            
            if $type != $cluster_fact['type'] {
                fail("Type of ${cluster} on ${host} mismatch ${type}: ${cluster_fact}")
            }
            
            # it does not really work with database protocols :(
            #$secure_host = ($cf_location != $cfdb_facts['cf_location'])
            $secure_host = false
            
            if $is_secure or $secure_host {
                # required for cname matching
                $addr = $host
            } else {
                $addr = pick($cluster_fact['host'], $host)
            }
            $port = $cluster_fact['port']

            if !$addr or !$port {
                fail("Invalid host/port for ${host}: ${cluster_fact}")
            }
            
            $host_under = regsubst($host, '\.', '_', 'G')
            $fw_service = "cfdbha_${cluster}_${port}"
            $fw_port = "any:${fw_service}:${host_under}"

            ensure_resource('cfnetwork::describe_service', $fw_service, {
                server => "tcp/${port}",
            })
            
            ensure_resource('cfnetwork::client_port', $fw_port, {
                dst  => $addr,
                user => $cfdb::haproxy::user,
            })
            
            $ret = {
                server => $host_under,
                addr => $addr,
                port => $port,
                backup => $cluster_fact['is_secondary'],
                secure => $secure_host,
            }
            $ret
        })
    }
    
    #---
    cfdb_haproxy_backend { $title:
        ensure          => present,
        type            => $type,
        cluster         => $cluster,
        role            => $role,
        password        => $password,
        access_user     => $access_user,
        max_connections => $max_connections,
        socket          => $socket,
        is_secure       => $is_secure,
        distribute_load => $distribute_load,
        cluster_addr    => $cluster_addr,
        require         => Cfdb_haproxy[$cfdb::haproxy::service_name],
    }
    
    #---
    if $type == 'mysql' {
        file { "${cfdb::haproxy::bin_dir}/check_${cluster}_${role}":
            ensure  => present,
            owner   => $cfdb::haproxy::user,
            group   => $cfdb::haproxy::user,
            mode    => '0750',
            content => epp("cfdb/health_check_${type}", {
                role     => $role,
                password => $password,
            }),
        }
    }
}
