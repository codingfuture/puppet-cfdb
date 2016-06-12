
class cfdb::mysql::clientpkg {
    assert_private()
    
    include cfdb::mysql
    
    $ver = $cfdb::mysql::actual_version
    
    # note: this matter for [ossible package conflicts
    if $cfdb::mysql::is_cluster {
        package { "percona-xtradb-client-${ver}": }
    } else {
        package { "percona-server-client-${ver}": }
    }
    
    # required for healthcheck script
    ensure_resource('package', 'python-mysqldb', {})
}
