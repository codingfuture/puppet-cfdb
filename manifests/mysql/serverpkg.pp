
class cfdb::mysql::serverpkg {
    assert_private()
    
    include cfdb::mysql
        
    if $cfdb::mysql::is_cluster {
        $ver = $cfdb::mysql::cluster_version
        $ver_nodot = regsubst($ver, '\.', '', 'G')
        package { "percona-xtradb-cluster-${ver_nodot}": }
    } else {
        $ver = $cfdb::mysql::version
        package { "percona-server-${ver}": }
    }

    # default instance must not run
    service { 'mysql':
        ensure => stopped,
        enable => false,
    }
}
