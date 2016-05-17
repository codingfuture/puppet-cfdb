
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
    
    #---
    $allowed_hosts = merge({
        localhost => $cfdb::max_connections_default,
    }, $access.reduce({}) |$memo, $val| {
        $certname = $val[0]
        $allowed =  $val[1]['cfdbaccess'][$cluster][$role]['client']
        
        $allowed_result = $allowed.reduce({}) |$imemo, $ival| {
            $maxconn = pick($ival['max_connections'], $cfdb::max_connections_default)
            $host = pick($ival['host'], $certname)
            
            if $certname == $::trusted['certname'] {
                $host_index = 'localhost'
            } else {
                $host_index = $host
            }

            merge($imemo, {
                $host_index => pick($imemo[$host_index], 0) + $maxconn
            })
        }
        
        merge($memo, $allowed_result)
    })
    
    #---
    cfdb_role { $title:
        ensure => present,
        cluster => $cluster,
        database => $database,
        user => "${database}${subname}",
        password => $q_password,
        custom_grant => $custom_grant,
        allowed_hosts => $allowed_hosts,
    }
    
    #---
    $port = try_get_value($::facts, "cf_persistent/ports/${cluster}")
    
    if $port {
        if !defined(Cfnetwork::Describe_service["cfdb_${cluster}"]) {
            cfnetwork::describe_service { "cfdb_${cluster}":
                server => "tcp/${port}",
            }
        }
        cfnetwork::service_port { "any:cfdb_${cluster}:${role}":
            src    => keys($allowed_hosts),
        }
    }
}