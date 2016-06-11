
class cfdb (
    $instances = {},
    $access = {},
    $iface = 'any',
    $root_dir = '/db',
    $max_connections_default = 10,
    $backup = true,
) {
    # global healthcheck db/role names
    $healthcheck = 'cfdbhealth'
    
    file { $root_dir:
        ensure => directory,
        mode   => '0555',
    }
    
    create_resources(cfdb::instance, $instances)
    create_resources(cfdb::access, $access)
}
