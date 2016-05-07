
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
    
    # TODO: Puppet DB query for access => max_conn
    $allowed_hosts = {
        localhost => 100,
    }
    
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