
define cfdb::access(
    $cluster,
    $role,
    $local_user,
    $use_proxy = 'auto',
    $readonly = false,
    $max_connections = $cfdb::max_connections_default,
    $config_prefix = 'DB_',
    $env_file = '.env',
) {
    #---
    if $use_proxy == 'auto' {
        $use_proxy_detected = false
        # TODO: setup HAProxy, if cluster with more than 1 instance
    } else {
        $use_proxy_detected = $use_proxy
    }
    
    #---
    if $use_proxy_detected == true {
        # TODO: setup load balancing, if $readonly
        fail('TODO: $use_proxy is not implemented yet')
    } elsif $use_proxy_detected == false {
        $cluster_facts_all = query_facts(
            "cfdb.${cluster}.is_secondary=false and cfdb.${cluster}.roles.${role}.present=true",
            ["cfdb"]
        )
        
        if empty($cluster_facts_all) {
            if defined(Cfdb::Instance[$cluster]) {
                # the only known instance is local
                # give it a chance
                $skip_run = true
                
                $cfg = {
                    'host' => 'localhost',
                    'port' => '',
                    'socket' => '',
                    'user' => $role,
                    'pass' => 'INVALID_PASSWORD',
                }
            } else {
                fail("Unknown cluster ${cluster} or associated role ${role}: $cluster_facts_all")
            }
        } else {
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
                }
            } else {
                $cfg = {
                    'host' => pick($cluster_fact['host'], $host),
                    'port' => $cluster_fact['port'],
                    'socket' => '',
                    'user' => $role,
                    'pass' => $role_fact['password'],
                }
            }
        }
    } else {
        fail('Invalid value for $use_proxy')
    }
    #---
    
    $cfg.each |$var, $val| {
        cfsystem::dotenv { "$title/${var}":
            user => $local_user,
            variable => "${config_prefix}${var}",
            value => $val,
            env_file => $env_file,
        }
    }
}
