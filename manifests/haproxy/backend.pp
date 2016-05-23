
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
    $cluster_facts_all = query_facts(
        "cfdb.${cluster}.present=true and cfdb.${cluster}.is_arbitrator=false",
        ['cfdb']
    )
    
    if empty($cluster_facts_all) {
        $cluster_addr = []
    } else {
        $cluster_addr = ($cluster_facts_all.map |$host, $cfdb_facts| {
            $cluster_fact = $cfdb_facts['cfdb'][$cluster]
            
            if $type != $cluster_fact['type'] {
                fail("Type of ${cluster} on ${host} mismatch ${type}: ${cluster_fact}")
            }
            
            $addr = pick($cluster_fact['host'], $host)
            $port = $cluster_fact['port']

            if !$addr or !$port {
                fail("Invalid host/port for ${host}: ${cluster_fact}")
            }
            
            $host_under = regsubst($host, '\.', '_', 'G')
            $fw_service = "cfdbha_${cluster}_${port}"
            $fw_port = "any:${fw_service}:${host_under}"

            if !defined(Cfnetwork::Describe_service[$fw_service]) {
                cfnetwork::describe_service { $fw_service:
                    server => "tcp/${port}",
                }
            }
            
            if !defined(Cfnetwork::Client_port[$fw_port]) {
                cfnetwork::client_port { $fw_port:
                    dst  => $addr,
                    user => $cfdb::haproxy::user,
                }
            }
            
            $ret = {
                server => $host_under,
                addr => $addr,
                port => $port,
                backup => $cluster_fact['is_secondary']
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
