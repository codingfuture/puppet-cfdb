#
# Copyright 2017 (c) Andrey Galkin
#


define cfdb::healthcheck(
    String[1]
        $type,
    String[1]
        $cluster,
    Optional[String[1]]
        $client_host,
    Boolean
        $add_haproxy = false,
) {
    assert_private()

    $healthcheck = $cfdb::healthcheck
    $healthcheck_access_title = "${cluster}/${healthcheck}"

    if !defined(Cfdb_access[$healthcheck_access_title]) {
        $healtcheck_info_raw = cfsystem::query([
            'from', 'resources', ['extract', [ 'certname', 'parameters' ],
                ['and',
                    ['=', 'type', 'Cfdb_role'],
                    ['=', ['parameter', 'cluster'], $cluster],
                    ['=', ['parameter', 'user'], $healthcheck],
                ],
        ]])


        $healthcheck_password = size($healtcheck_info_raw) ? {
            0       => defined(Cfdb_role["${cluster}/${healthcheck}"]) ? {
                true => getparam(Cfdb_role["${cluster}/${healthcheck}"], 'password'),
                default => $healthcheck # temporary,
            },
            default => $healtcheck_info_raw[0]['parameters']['password']
        }

        cfdb_access{ $healthcheck_access_title:
            ensure          => present,
            cluster         => $cluster,
            role            => $healthcheck,
            local_user      => undef,
            max_connections => 2,
            client_host     => $client_host,
            config_info     => {},
            require         => Anchor['cfnetwork:firewall'],
        }


        if $add_haproxy {
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
}
