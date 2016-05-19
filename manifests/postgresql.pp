
class cfdb::postgresql (
    $is_cluster = false,
    $version = '9.5',
) {
    include stdlib
    include cfdb
    include cfdb::postgresql::aptrepo
    
    if $is_cluster {
        fail("is_cluster is not supported")
    }
}
