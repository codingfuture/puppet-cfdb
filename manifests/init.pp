
class cfdb (
    $root_dir = '/db',
    $instances = {},
) {
    create_resources(cfdb::instance, $instances)
}
