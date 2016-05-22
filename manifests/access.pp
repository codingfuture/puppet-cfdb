
define cfdb::access(
    $cluster,
    $role,
    $local_user,
    $use_proxy = 'auto',
    $max_connections = $cfdb::max_connections_default,
    $config_prefix = 'DB_',
    $env_file = '.env',
    $iface = $cfdb::iface,
) {
    include cfnetwork
    
    #---
    if $iface == 'any' {
        $client_host = undef
    } elsif defined(Cfnetwork::Iface[$iface]) {
        $client_host = pick_default(getparam(Cfnetwork::Iface[$iface], 'address'), undef)
    } else {
        $client_host = $iface
    }
    
    cfdb_access { $title:
        ensure          => present,
        cluster         => $cluster,
        role            => $role,
        max_connections => $max_connections,
        client_host     => $client_host,
    }
    
    #---
    if $use_proxy == 'auto' {
        $use_proxy_detected = (size(query_facts(
            "cfdb.${cluster}.present=true",
            ['cfdb']
        )) > 1)
    } else {
        $use_proxy_detected = $use_proxy
    }
    
    #---
    $cluster_facts_all = query_facts(
        "cfdb.${cluster}.is_secondary=false and cfdb.${cluster}.roles.${role}.present=true",
        ['cfdb']
    )
    
    if empty($cluster_facts_all) {
        if defined(Cfdb::Instance[$cluster]) {
            # the only known instance is local
            # give it a chance
            $cfg = {
                'host' => 'localhost',
                'port' => '',
                'socket' => '',
                'user' => $role,
                'pass' => 'INVALID_PASSWORD',
                'type' => 'UNKNOWN',
            }
        } else {
            fail("Unknown cluster ${cluster} or associated role ${role}: ${cluster_facts_all}")
        }
    } elsif $use_proxy_detected == true or $use_proxy_detected == 'secure' {
        $cluster_fact = values($cluster_facts_all)[0]['cfdb'][$cluster]
        $role_fact = $cluster_fact['roles'][$role]
        $type = $cluster_fact['type']
        $socket = "/run/cfhaproxy/${type}_${cluster}.sock"
        
        cfdb::haproxy::backend{ "${cluster}/${role}":
            type => $type,
            cluster => $cluster,
            max_connections => $max_connections,
            role => $role,
            password => $role_fact['password'],
            socket => $socket,
            is_secure => ($use_proxy_detected == 'secure'),
            distribute_load => $role_fact['readonly'],
        }
        
        $cfg = {
            'host' => 'localhost',
            'port' => '',
            'socket' => $socket,
            'user' => $role,
            'pass' => $role_fact['password'],
            'type' => $type,
        }
    } elsif $use_proxy_detected == false {
        $cluster_fact = values($cluster_facts_all)[0]['cfdb'][$cluster]
        $role_fact = $cluster_fact['roles'][$role]
        $host = keys($cluster_facts_all)[0]
        
        if $host == $::trusted['certname'] {
            $cfg = {
                'host' => 'localhost',
                'port' => $cluster_fact['port'],
                'socket' => $cluster_fact['socket'],
                'user' => $role,
                'pass' => $role_fact['password'],
                'type' => $cluster_fact['type'],
            }
        } else {
            $cfg = {
                'host' => pick($cluster_fact['host'], $host),
                'port' => $cluster_fact['port'],
                'socket' => '',
                'user' => $role,
                'pass' => $role_fact['password'],
                'type' => $cluster_fact['type'],
            }
        }
        
        $type = $cluster_fact['type']
        include "cfdb::${type}::clientpkg"
    } else {
        fail('Invalid value for $use_proxy')
    }
    #---
    $cfg.each |$var, $val| {
        cfsystem::dotenv { "${title}/${var}":
            user     => $local_user,
            variable => upcase("${config_prefix}${var}"),
            value    => $val,
            env_file => $env_file,
        }
    }
    
    #---
    if $cfg['port'] != '' {
        if !defined(Cfnetwork::Describe_service["cfdb_${cluster}"]) {
            $port = $cfg['port']
            cfnetwork::describe_service { "cfdb_${cluster}":
                server => "tcp/${port}",
            }
        }
        if !defined(Cfnetwork::Client_port["any:cfdb_${cluster}:${local_user}"]) {
            cfnetwork::client_port { "any:cfdb_${cluster}:${local_user}":
                dst  => $cfg['host'],
                user => $local_user,
            }
        }
    }
}
