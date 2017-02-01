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
    $access = cf_query_facts("cfdbaccess.${cluster}.roles.${role}.present=true", ['cfdbaccess'])

    $q_password = cf_genpass("cfdb/${cluster}@${role}", 16, $password)

    #---
    $allowed_hosts = merge(
        {
            localhost => $cfdb::max_connections_default,
        },
        $static_access,
        $access.reduce({}) |$memo, $val| {
            $certname = $val[0]
            $allowed =  $val[1]['cfdbaccess'][$cluster]['roles'][$role]['client']

            $allowed_result = $allowed.reduce({}) |$imemo, $ival| {
                $maxconn = pick($ival['max_connections'], $cfdb::max_connections_default)
                $host = pick($ival['host'], $certname).split('/')[0]

                if $certname == $::trusted['certname'] {
                    $host_index = 'localhost'
                } else {
                    $host_index = $host
                }

                # make sure to add +1 per every role for possible health checks, etc.
                merge($imemo, {
                    $host_index => pick($imemo[$host_index], 0) + $maxconn + 1
                })
            }

            merge($memo, $allowed_result)
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
        allowed_hosts => $allowed_hosts,
    }
}
