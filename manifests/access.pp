#
# Copyright 2016-2017 (c) Andrey Galkin
#


define cfdb::access(
    $cluster,
    $role,
    $local_user,
    $use_proxy = 'auto',
    $max_connections = $cfdb::max_connections_default,
    $config_prefix = 'DB_',
    $env_file = '.env',
    $iface = $cfdb::iface,
    $custom_config = undef,
    $use_unix_socket = true,
    $fallback_db = undef,
    $distribute_load = undef,
) {
    include cfnetwork
    include cfsystem::custombin
    #---
    $access_checker = "${cfsystem::custombin::bin_dir}/cfdb_access_checker"
    ensure_resource('file', $access_checker, {
        mode    => '0555',
        content => file('cfdb/cfdb_access_checker.py'),
    })

    #---
    $resource_title = $distribute_load ? {
        true    => "${cluster}:${role}:${local_user}:dl",
        default => "${cluster}:${role}:${local_user}",
    }
    $localhost = $use_unix_socket ? {
        false    => '127.0.0.1',
        default => 'localhost',
    }
    $max_connections_reserve = $max_connections + 2

    #---
    if $iface == 'any' {
        $client_host = undef
    } else {
        $client_host = cf_get_bind_address($iface)
    }

    #---
    if $use_proxy == 'auto' {
        $use_proxy_detected = (size(cf_query_facts(
            "cfdb.${cluster}.present=true",
            ['cfdb']
        )) > 1)
    } else {
        $use_proxy_detected = $use_proxy
    }

    #---
    $cluster_facts_all = cf_query_facts(
        "cfdb.${cluster}.is_secondary=false and cfdb.${cluster}.roles.${role}.present=true",
        ['cfdb']
    )

    if empty($cluster_facts_all) {
        if defined(Cfdb::Instance[$cluster]) {
            # the only known instance is local
            # give it a chance
            # NOTE: in case access is critical after the first Puppet run, please make sure
            #       to use $static_access parameter for role definition!
            $port = cf_genport($cluster, getparam(Cfdb::Instance[$cluster], 'port'))
            $type = getparam(Cfdb::Instance[$cluster], 'type')

            $cfg = {
                'host'    => $localhost,
                'port'    => $port,
                'socket'  => '',
                'user'    => $role,
                'pass'    => cf_genpass("cfdb/${cluster}@${role}", 16),
                'db'      => pick(getparam(Cfdb::Role["${cluster}/${role}"], 'database'), $fallback_db, $role),
                'type'    => $type,
                'maxconn' => $max_connections,
            }

            $fw_service = "cfdb_${cluster}_${port}"
            ensure_resource('cfnetwork::describe_service', $fw_service, {
                server => "tcp/${port}",
            })
            ensure_resource('cfnetwork::service_port', "local:${fw_service}", {})
            ensure_resource('cfnetwork::client_port', "local:${fw_service}:${local_user}", {
                user => $local_user,
            })

            include "cfdb::${type}::clientpkg"

            if empty($type) {
                fail("Unable to get type from Cfdb::Instance[${cluster}]")
            }

            if empty($cfg['db']) {
                fail("Unable to get database from Cfdb::Role[${cluster}/${role}]")
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

        $port = cf_genport("cfha/${resource_title}")
        $port_name = "${type}_${cluster}_${role}_${local_user}"

        if $use_unix_socket {
            $host = 'localhost'
            case $type {
                'postgresql' : {
                    $cfg_socket = "/var/lib/${port_name}"
                    $socket = "${cfg_socket}/.s.PGSQL.${port}"

                    # HAProxy creates socket in this folder
                    file { $cfg_socket:
                        ensure => directory,
                        mode   => '0755',
                        notify => Cfdb::Haproxy::Frontend[$resource_title],
                    }
                }
                default: {
                    $socket = "/run/cfdbhaproxy/${port_name}.sock"
                    $cfg_socket = $socket
                }
            }
        } else {
            $host = '127.0.0.1'
            $socket = ''
            $cfg_socket = ''

            $fw_service = "cfdb_${cluster}_${port}"
            ensure_resource('cfnetwork::describe_service', $fw_service, {
                server => "tcp/${port}",
            })
            ensure_resource('cfnetwork::service_port', "local:${fw_service}", {})
            ensure_resource('cfnetwork::client_port', "local:${fw_service}:${local_user}", {
                user => $local_user,
            })
        }

        cfdb::haproxy::frontend{ $resource_title:
            type            => $type,
            cluster         => $cluster,
            max_connections => $max_connections_reserve,
            access_user     => $local_user,
            socket          => $socket,
            secure_mode     => $use_proxy_detected,
            distribute_load => pick($distribute_load, $role_fact['readonly']),
            client_host     => $client_host,
            use_unix_socket => $use_unix_socket,
            local_port      => $port,
        }

        $cfg = {
            'host'    => $host,
            'port'    => $port,
            'socket'  => $cfg_socket,
            'user'    => $role,
            'pass'    => $role_fact['password'],
            'db'      => $role_fact['database'],
            'type'    => $type,
            'maxconn' => $max_connections,
        }
    } elsif $use_proxy_detected == false {
        $cluster_fact = values($cluster_facts_all)[0]['cfdb'][$cluster]
        $role_fact = $cluster_fact['roles'][$role]
        $host = keys($cluster_facts_all)[0]
        $port = $cluster_fact['port']

        $fw_service = "cfdb_${cluster}_${port}"
        ensure_resource('cfnetwork::describe_service', $fw_service, {
            server => "tcp/${port}",
        })

        if $host == $::trusted['certname'] {
            $cfg = {
                'host'    => $localhost,
                'port'    => $cluster_fact['port'],
                'socket'  => $cluster_fact['socket'],
                'user'    => $role,
                'pass'    => $role_fact['password'],
                'db'      => $role_fact['database'],
                'type'    => $cluster_fact['type'],
                'maxconn' => $max_connections,
            }

            $fw_port = "local:${fw_service}:${local_user}"

            ensure_resource('cfnetwork::client_port', $fw_port, {
                user => $local_user,
            })
        } else {
            $addr = pick($cluster_fact['host'], $host)
            $cfg = {
                'host'    => $addr,
                'port'    => $port,
                'socket'  => '',
                'user'    => $role,
                'pass'    => $role_fact['password'],
                'db'      => $role_fact['database'],
                'type'    => $cluster_fact['type'],
                'maxconn' => $max_connections,
            }

            $fw_port = "any:${fw_service}:${local_user}"

            ensure_resource('cfnetwork::client_port', $fw_port, {
                dst  => $addr,
                user => $local_user,
            })

            cfdb::require_endpoint{ "${resource_title}:${host}":
                cluster => $cluster,
                host    => $host,
                source  => $::trusted['certname'],
                maxconn => $max_connections_reserve,
                secure  => false,
            }
        }

        $type = $cluster_fact['type']
        include "cfdb::${type}::clientpkg"
    } else {
        fail('Invalid value for $use_proxy')
    }

    # DB type specific extras
    #---
    case $type {
        'postgresql': {
            if $cfg['socket'] != '' {
                $psql_socket = regsubst(regsubst($cfg['socket'],
                    '\\+', '%2B', 'G'),
                    '/', '%2F', 'G')
                $conninfo_socket = "?host=${psql_socket}"
            } else {
                $conninfo_socket = ''
            }
            $uri_pass = regsubst(regsubst($cfg['pass'],
                '\\+', '%2B', 'G'),
                '/', '%2F', 'G')
            $cfg_all = merge($cfg, {
                'conninfo' => [
                    "postgresql://${cfg['user']}:",
                    "${uri_pass}@",
                    "${cfg['host']}:",
                    "${cfg['port']}/",
                    $cfg['db'],
                    $conninfo_socket,
                ].join('')
            })
        }
        default: {
            $cfg_all = $cfg
        }
    }

    #---
    $cfg_all.each |$var, $val| {
        cfsystem::dotenv { "${resource_title}:${var}":
            user     => $local_user,
            variable => upcase("${config_prefix}${var}"),
            value    => $val,
            env_file => $env_file,
        }
    }

    #---
    cfdb_access { $title:
        ensure          => present,
        cluster         => $cluster,
        role            => $role,
        local_user      => $local_user,
        max_connections => $max_connections_reserve,
        client_host     => $client_host,
        config_info     => {
            'dotenv' => $env_file,
            'prefix' => $config_prefix,
        },
        require         => [
            File[$access_checker],
        ],
    }

    #---
    if $custom_config {
        create_resources($custom_config, {
            "${title}" => {
                cluster         => $cluster,
                role            => $role,
                local_user      => $local_user,
                config_vars     => $cfg_all,
            }
        })
    }
}
