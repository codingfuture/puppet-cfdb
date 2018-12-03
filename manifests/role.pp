#
# Copyright 2016-2018 (c) Andrey Galkin
#


define cfdb::role(
    String[1]
        $cluster,
    String[1]
        $database,
    Optional[String[1]]
        $password = undef,
    String[0]
        $subname = '',
    Boolean
        $readonly = false,
    Optional[String[1]]
        $custom_grant = undef,
    Hash[String[1], Integer[1]]
        $static_access = {},
) {
    $role = "${database}${subname}"

    $access = cfsystem::query([
        'from', 'resources', ['extract', [ 'certname', 'parameters' ],
            ['and',
                ['=', 'type', 'Cfdb_access'],
                ['=', ['parameter', 'cluster'], $cluster],
                ['=', ['parameter', 'role'], $role],
            ],
    ]])

    $secret_title = "cfdb/${cluster}@${role}"
    $q_password = cfsystem::gen_pass($secret_title, 16, $password)

    #---
    $allowed_hosts = merge(
        {
            localhost => $cfdb::max_connections_default,
        },
        $static_access,
        $access.reduce({}) |$memo, $val| {
            $certname = $val['certname']
            $params = $val['parameters']

            $maxconn = pick($params['max_connections'], $cfdb::max_connections_default)
            $host = pick($params['client_host'], $certname).split('/')[0]

            if $host == $::trusted['certname'] {
                $host_index = 'localhost'
            } else {
                $host_index = $host
            }

            merge($memo, {
                $host_index => pick($memo[$host_index], 0) + $maxconn
            })
        }
    )

    #---
    cfdb_role { $title:
        ensure        => present,
        cluster       => $cluster,
        database      => $database,
        user          => "${database}${subname}",
        password      => $q_password,
        readonly      => $readonly,
        custom_grant  => $custom_grant,
        allowed_hosts => cfsystem::stable_sort($allowed_hosts),
    }
}
