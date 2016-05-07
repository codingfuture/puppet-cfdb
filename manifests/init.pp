
class cfdb (
    $root_dir = '/db',
    $instances = {},
    $access = {},
) {
    file { $root_dir:
        ensure => directory,
        mode => '0555',
    }
    
    create_resources(cfdb::instance, $instances)
    create_resources(cfdb::access, $access)
}
