#
# Copyright 2016-2019 (c) Andrey Galkin
#


define cfdb::access(
    String[1]
        $cluster,
    String[1]
        $local_user,
    String[1]
        $role = $cluster,
    Variant[Boolean, Enum['auto', 'secure', 'insecure']]
        $use_proxy = 'auto',
    Integer[1]
        $max_connections = $cfdb::max_connections_default,
    String[1]
        $config_prefix = 'DB_',
    String[1]
        $env_file = '.env',
    String[1]
        $iface = $cfdb::iface,
    String[1]
        $local_iface = 'local',
    Optional[String[1]]
        $custom_config = undef,
    Boolean
        $use_unix_socket = true,
    Optional[String[1]]
        $fallback_db = undef,
    Optional[Boolean]
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
    $cluster_instances = cfsystem::query([
        'from', 'resources', ['extract', [ 'certname', 'parameters' ],
            ['and',
                ['=', 'type', 'Cfdb_instance'],
                ['=', 'title', $cluster],
                ['=', ['parameter', 'is_arbitrator'], false]
            ],
    ]])

    $cluster_info = $cluster_instances.reduce(undef) |$memo, $val| {
        $params = $val['parameters']

        if !$params['is_secondary'] {
            $type = $params['type']
            $service_name = $params['service_name']
            $cfdb = $params['settings_tune']['cfdb']
            $socket = $type ? {
                'postgresql' => "/run/${service_name}",
                default      => "/run/${service_name}/service.sock"
            }

            $res = {
                'certname'   => $val['certname'],
                'type'       => $params['type'],
                'is_cluster' => $params['is_cluster'],
                'host'       => pick(
                    $cfdb['listen'],
                    $val['certname']
                ),
                'port'       => $cfdb['port'],
                'socket'     => $socket,
            }
        } else {
            $memo
        }
    }
    $is_local_cluster = $cluster_info and ($cluster_info['certname'] == $::trusted['certname'])

    #---
    $resource_title = $distribute_load ? {
        true    => "${cluster}:${role}:${local_user}:dl",
        default => "${cluster}:${role}:${local_user}",
    }
    $local_host = $use_unix_socket ? {
        false   => cfnetwork::bind_address($local_iface),
        default => 'localhost',
    }
    $max_connections_reserve = $max_connections + 2

    #---
    $use_proxy_detected = $use_proxy ? {
        'auto'  => ($cluster_info and $cluster_info['is_cluster']
            ) or (
                    defined(Cfdb::Instance[$cluster]) and
                    getparam(Cfdb::Instance[$cluster], 'is_cluster')
            ),
        default => $use_proxy
    }

    #---
    $client_host = $iface ? {
        'any'    => undef,
        'docker' => ($is_local_cluster and !$use_proxy_detected) ? {
            true    => '172.18.0.0/16',
            default => undef
        },
        default  => cfnetwork::bind_address($iface)
    }

    #---
    $role_info_raw = cfsystem::query([
        'from', 'resources', ['extract', [ 'certname', 'parameters' ],
            ['and',
                ['=', 'type', 'Cfdb_role'],
                ['=', ['parameter', 'cluster'], $cluster],
                ['=', ['parameter', 'user'], $role],
            ],
    ]])

    $role_info = size($role_info_raw) ? {
        0       => undef,
        default => $role_info_raw[0]['parameters']
    }

    if !$role_info or !$cluster_info {
        $cluster_rsc = Cfdb::Instance[$cluster]

        if defined($cluster_rsc) {
            $rsc_port = getparam($cluster_rsc, 'port')
            $rsc_port_pick = $rsc_port ? {
                ''      => undef,
                undef   => undef,
                default => Integer($rsc_port)
            }

            # the only known instance is local
            # give it a chance
            # NOTE: in case access is critical after the first Puppet run, please make sure
            #       to use $static_access parameter for role definition!
            $port = cfsystem::gen_port($cluster, $rsc_port_pick)
            $type = getparam($cluster_rsc, 'type')

            $cfg = {
                'host'    => $local_host,
                'port'    => $port,
                'socket'  => '',
                'user'    => $role,
                'pass'    => cfsystem::gen_pass("cfdb/${cluster}@${role}", 16),
                'db'      => pick(getparam(Cfdb_role["${cluster}/${role}"], 'database'), $fallback_db, $role),
                'type'    => $type,
                'maxconn' => $max_connections,
            }

            $fw_service = "cfdb_${cluster}_${port}"
            ensure_resource('cfnetwork::describe_service', $fw_service, {
                server => "tcp/${port}",
            })
            ensure_resource('cfnetwork::service_port', "${local_iface}:${fw_service}", {})
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
            fail("Unknown cluster ${cluster} or associated role ${role}")
        }
    } elsif $use_proxy_detected != false {
        case $use_proxy_detected {
            'secure', 'insecure', true: {}
            default: {
                fail("Unknown \$use_proxy parameter: ${use_proxy_detected}")
            }
        }

        $type = $cluster_info['type']

        $port_persist = "cfha/${resource_title}"
        $port_name = "${type}_${cluster}_${role}_${local_user}"
        $port = cfsystem::gen_port($port_persist)

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
            $host = $local_host
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

            if $local_iface != 'local' {
                ensure_resource('cfnetwork::service_port', "${local_iface}:${fw_service}", {})
            }
        }

        cfdb::haproxy::frontend{ $resource_title:
            type            => $type,
            cluster         => $cluster,
            max_connections => $max_connections_reserve,
            access_user     => $local_user,
            socket          => $socket,
            secure_mode     => $use_proxy_detected,
            distribute_load => pick($distribute_load, $role_info['readonly']),
            client_host     => $client_host,
            use_unix_socket => $use_unix_socket,
            local_host      => $local_host,
            local_port      => $port,
        }

        $cfg = {
            'host'    => $host,
            'port'    => $port,
            'socket'  => $cfg_socket,
            'user'    => $role,
            'pass'    => $role_info['password'],
            'db'      => $role_info['database'],
            'type'    => $type,
            'maxconn' => $max_connections,
        }
    } elsif $use_proxy_detected == false {
        $type = $cluster_info['type']
        $port = $cluster_info['port']

        $fw_service = "cfdb_${cluster}_${port}"
        ensure_resource('cfnetwork::describe_service', $fw_service, {
            server => "tcp/${port}",
        })

        if $cluster_info['certname'] == $::trusted['certname'] {
            $host = $local_host

            if $use_unix_socket {
                $socket = $cluster_info['socket']
            } else {
                $socket = ''
            }

            $fw_port = "local:${fw_service}:${local_user}"

            ensure_resource('cfnetwork::client_port', $fw_port, {
                user => $local_user,
            })

            if $local_iface != 'local' {
                ensure_resource('cfnetwork::service_port', "${local_iface}:${fw_service}", {})
            }
        } else {
            $host = $cluster_info['host']
            $socket = ''

            $fw_port = "any:${fw_service}:${local_user}"

            ensure_resource('cfnetwork::client_port', $fw_port, {
                dst  => $cluster_info['host'],
                user => $local_user,
            })

            if $local_iface != 'local' {
                $fw_router_port = "${local_iface}/any:${fw_service}:${local_user}"

                ensure_resource('cfnetwork::router_port', $fw_router_port, {
                    dst  => $cluster_info['host']
                })
            }

            cfdb::require_endpoint{ "${resource_title}:${host}":
                cluster => $cluster,
                host    => $cluster_info['certname'],
                source  => $::trusted['certname'],
                maxconn => $max_connections_reserve,
                secure  => false,
            }

            ensure_resource('cfdb::healthcheck', $cluster, {
                type        => $type,
                cluster     => $cluster,
                client_host => $client_host,
            })
        }

        $cfg = {
            'host'    => $host,
            'port'    => $port,
            'socket'  => $socket,
            'user'    => $role,
            'pass'    => $role_info['password'],
            'db'      => $role_info['database'],
            'type'    => $cluster_info['type'],
            'maxconn' => $max_connections,
        }

        include "cfdb::${type}::clientpkg"
    } else {
        fail('Invalid value for $use_proxy')
    }

    # DB type specific extras
    #---
    case $type {
        'elasticsearch': {
            if $use_proxy_detected == 'secure' {
                $cfg_all = $cfg
            } else {
                $nodes = $cluster_instances.reduce([]) |$memo, $val| {
                    $params = $val['parameters']
                    $cfdb = $params['settings_tune']['cfdb']
                    $host = pick(
                        $cfdb['listen'],
                        $val['certname']
                    )
                    $memo + $host
                }

                if $cluster_info {
                    $nodeport = cfdb::derived_port($cluster_info['port'], 'elasticsearch')
                } else {
                    $nodeport = cfdb::derived_port($port, 'elasticsearch')
                }

                $sorted_nodes = cfsystem::stable_sort($nodes)
                $cfg_all = merge( $cfg, {
                    nodes    => $sorted_nodes.join(' '),
                    nodeport => $nodeport,
                } )

                # Allow direct access for peer protocol
                $fw_peer_service = "cfdb_${cluster}_peeraccess"
                ensure_resource('cfnetwork::describe_service', $fw_peer_service, {
                    server => "tcp/${nodeport}",
                })
                ensure_resource('cfnetwork::client_port', "any:${fw_peer_service}:${local_user}", {
                    user => $local_user,
                    dst  => $sorted_nodes,
                })

                if $local_iface != 'local' {
                    ensure_resource(
                        'cfnetwork::router_port',
                        "${local_iface}/any:${fw_peer_service}:${local_user}",
                        {
                            dst => $sorted_nodes,
                        })

                    if defined(Cfdb::Instance[$cluster]) {
                        ensure_resource('cfnetwork::service_port', "${local_iface}:${fw_peer_service}")
                    }
                }
            }
        }
        'mongodb',
        'redis': {
            if $use_proxy_detected == 'secure' {
                $cfg_all = $cfg
            } else {
                $nodes = $cluster_instances.reduce([]) |$memo, $val| {
                    $params = $val['parameters']
                    $cfdb = $params['settings_tune']['cfdb']
                    $host = pick(
                        $cfdb['listen'],
                        $val['certname']
                    )
                    $memo + $host
                }

                if $cluster_info {
                    $node_port = $cluster_info['port']
                } else {
                    $node_port = $port
                }

                $sorted_nodes = cfsystem::stable_sort($nodes)
                $cfg_all = merge( $cfg, {
                    nodes    => $sorted_nodes.join(' '),
                    nodeport => $node_port,
                } )

                # Allow direct access for peer protocol
                $fw_peer_service = "cfdb_${cluster}_peeraccess"
                ensure_resource('cfnetwork::describe_service', $fw_peer_service, {
                    server => "tcp/${node_port}",
                })
                ensure_resource('cfnetwork::client_port', "any:${fw_peer_service}:${local_user}", {
                    user => $local_user,
                    dst  => $sorted_nodes,
                })

                if $local_iface != 'local' {
                    ensure_resource(
                        'cfnetwork::router_port',
                        "${local_iface}/any:${fw_peer_service}:${local_user}",
                        {
                            dst => $sorted_nodes,
                        })

                    if defined(Cfdb::Instance[$cluster]) {
                        ensure_resource('cfnetwork::service_port', "${local_iface}:${fw_peer_service}")
                    }
                }
            }
        }
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
            before   => Cfdb_access[$title],
        }
    }

    #---
    if (($use_proxy_detected == false) and
        $cluster_info and
        ($cluster_info['certname'] == $::trusted['certname'])) {
        $client_access_host = pick($client_host, $local_host)
    } else {
        $client_access_host = $client_host
    }

    #---
    cfdb_access { $title:
        ensure          => present,
        cluster         => $cluster,
        role            => $role,
        local_user      => $local_user,
        max_connections => $max_connections_reserve,
        client_host     => $client_access_host,
        config_info     => {
            'dotenv' => $env_file,
            'prefix' => $config_prefix,
        },
        use_proxy       => $use_proxy_detected,
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
