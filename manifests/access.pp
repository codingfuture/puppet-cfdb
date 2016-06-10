
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
    $resource_title = "${cluster}:${role}:${local_user}"
    
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
    } elsif $use_proxy_detected != false {
        case $use_proxy_detected {
            'secure', 'insecure', true: {}
            default: {
                fail("Unknown \$use_proxy parameter: ${use_proxy_detected}")
            }
        }
        
        $cluster_fact = values($cluster_facts_all)[0]['cfdb'][$cluster]
        $role_fact = $cluster_fact['roles'][$role]
        $type = $cluster_fact['type']
        
        case $type {
            'postgresql' : {
                $fake_port = 1234
                $cfg_socket = "/var/tmp/${type}_${cluster}_${role}_${local_user}"
                $socket = "${cfg_socket}/.s.PGSQL.${fake_port}"
                
                file { $cfg_socket:
                    ensure => directory,
                    mode   => '0775',
                    notify => Cfdb::Haproxy::Frontend[$resource_title],
                }
            }
            default: {
                $fake_port = ''
                $socket = "/run/cfhaproxy/${type}_${cluster}_${role}_${local_user}.sock"
                $cfg_socket = $socket
            }
        }
        
        cfdb::haproxy::frontend{ $resource_title:
            type            => $type,
            cluster         => $cluster,
            max_connections => $max_connections,
            role            => $role,
            password        => $role_fact['password'],
            database        => $role_fact['database'],
            access_user     => $local_user,
            socket          => $socket,
            secure_mode     => $use_proxy_detected,
            distribute_load => $role_fact['readonly'],
        }
        
        $cfg = {
            'host'  => 'localhost',
            'port'  => "${fake_port}",
            'socket' => $cfg_socket,
            'user'  => $role,
            'pass'  => $role_fact['password'],
            'db'    => $role_fact['database'],
            'type'  => $type,
        }
    } elsif $use_proxy_detected == false {
        $cluster_fact = values($cluster_facts_all)[0]['cfdb'][$cluster]
        $role_fact = $cluster_fact['roles'][$role]
        $host = keys($cluster_facts_all)[0]
        
        if $host == $::trusted['certname'] {
            $cfg = {
                'host' => 'localhost',
                'port' => "${cluster_fact['port']}",
                'socket' => $cluster_fact['socket'],
                'user' => $role,
                'pass' => $role_fact['password'],
                'db'    => $role_fact['database'],
                'type' => $cluster_fact['type'],
            }
        } else {
            $cfg = {
                'host' => pick($cluster_fact['host'], $host),
                'port' => "${cluster_fact['port']}",
                'socket' => '',
                'user' => $role,
                'pass' => $role_fact['password'],
                'db'    => $role_fact['database'],
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
        cfsystem::dotenv { "${resource_title}:${var}":
            user     => $local_user,
            variable => upcase("${config_prefix}${var}"),
            value    => $val,
            env_file => $env_file,
        }
    }
    
    # DB type specific extras
    case $type {
        'postgresql' : {
            if $cfg['socket'] != '' {
                $conninfo_socket = "?host=${uriescape($cfg['socket'])}"
            } else {
                $conninfo_socket = ''
            }
            cfsystem::dotenv { "${resource_title}:conninfo":
                user     => $local_user,
                variable => upcase("${config_prefix}conninfo"),
                value    => [
                    "postgresql://${uriescape($cfg['user'])}:",
                    "${uriescape($cfg['pass'])}@",
                    "${uriescape($cfg['host'])}:",
                    "${uriescape($cfg['port'])}/",
                    "${uriescape($cfg['db'])}",
                    $conninfo_socket,
                ].join(''),
                env_file => $env_file,
            }
        }
    }
    
    
    #---
    $port = $cfg['port']
    if $port and ($port != '') {
        ensure_resource('cfnetwork::describe_service', "cfdb_${cluster}", {
            server => "tcp/${port}",
        })
        ensure_resource('cfnetwork::client_port', "any:cfdb_${cluster}:${local_user}", {
            dst  => $cfg['host'],
            user => $local_user,
        })
    }
}
