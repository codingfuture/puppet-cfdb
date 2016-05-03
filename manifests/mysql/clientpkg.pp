
class cfdb::mysql::clientpkg {
    assert_private()
    
    include cfdb::mysql
    
    # note: this matter for [ossible package conflicts
    if $cfdb::mysql::is_cluster {
        $ver = $cfdb::mysql::cluster_version
        package { "percona-xtradb-client-${ver}" }
    } else {
        $ver = $cfdb::mysql::version
        package { "percona-client-${ver}" }
    }
}
