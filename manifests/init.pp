
class cfdb (
    $root_dir = '/db',
    $instances = {},
) {
    create_resources(cfdb::instance, $instances)
    
    file { $root_dir:
        ensure => directory,
        mode => '0555',
    }
}
