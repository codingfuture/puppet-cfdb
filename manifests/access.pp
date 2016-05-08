
define cfdb::access(
    $cluster,
    $role,
    $local_user,
    $domain = $::trusted['domain'],
    $outgoing_face = 'any',
    $max_connections = 10,
    $config_prefix = 'DB_',
    $env_file = undef,
) {
    
    $cfg = {
        'host' => 'test',
        'port' => '',
        'socket' => '',
        'user' => '',
        'pass' => '',
    }
    
    $cfg.each |$var, $val| {
        cfsystem::dotenv { "$title/${var}":
            user => $local_user,
            variable => "${config_prefix}${var}",
            value => $val,
            env_file => $env_file,
        }
    }
}
