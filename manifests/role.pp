#
# Copyright 2016-2017 (c) Andrey Galkin
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
    # Note: there is a limitation of PuppetDB query: filter by single parameter only
    $q = "(Cfdb_access[~'.*']{ cluster = '${cluster}' } and Cfdb_access[~'.*']{ role = '${role}' })"
    $access = cf_query_resources($q, $q, false)

    $secret_title = "cfdb/${cluster}@${role}"
    $q_password = cf_genpass($secret_title, 16, $password)

    cfsystem_persist { "secrets:${secret_title}":
        section => 'secrets',
        key     => $secret_title,
        value   => $q_password,
    }


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
            $host = pick($params['host'], $certname).split('/')[0]

            if $certname == $::trusted['certname'] {
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
        allowed_hosts => cf_stable_sort($allowed_hosts),
    }
}
