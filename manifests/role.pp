
define cfdb::role(
    $cluster,
    $database,
    $password = undef,
    $subname = '',
    $custom_grant = undef,
) {
    if $password {
        $q_password = $password
    } else {
        $dig_key = "cf_persistent/cfdb_passwd/${cluster}@${database}"
        #$dig_password = dig($::facts, ['cf_persistent', 'cfdb_passwd', $title])
        $dig_password = try_get_value($::facts, $dig_key)
        
        if $dig_password {
            $q_password = $dig_password
        } else {
            $q_password = cf_genpass(16)
        }
    }
    
    $role = "${database}${subname}"
    # Note: there is a limitation of PuppetDB query: filter by single parameter only
    $access = query_facts("cfdbaccess.${cluster}.${role}.present=true", ['cfdbaccess'])
    
    $allowed_hosts = merge({
        localhost => $cfdb::max_connections_default,
    }, $access.reduce({}) |$memo, $val| {
        $certname = $val[0]
        $role_fact = $val[1]['cfdbaccess'][$cluster][$role]
        
        $maxconn = pick($role_fact['max_connections'], $cfdb::max_connections_default)
        $host = pick($role_fact['host'], $certname)
        merge($memo, {
            $host => pick($memo[$host], 0) + $maxconn
        })
    })
    
    cfdb_role { $title:
        ensure => present,
        cluster => $cluster,
        database => $database,
        user => "${database}${subname}",
        password => $q_password,
        custom_grant => $custom_grant,
        allowed_hosts => $allowed_hosts,
    }
}