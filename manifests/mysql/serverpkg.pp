
class cfdb::mysql::serverpkg {
    assert_private()
    
    include cfdb
    include cfdb::mysql
        
    if $cfdb::mysql::is_cluster {
        $ver = $cfdb::mysql::cluster_version
        $ver_nodot = regsubst($ver, '\.', '', 'G')
        package { "percona-xtradb-cluster-${ver_nodot}": }
    } else {
        $ver = $cfdb::mysql::version
        package { "percona-server-server-${ver}": }
    }
    
    package { "percona-xtrabackup-24": }
    package { "qpress": }

    # default instance must not run
    service { 'mysql':
        ensure => stopped,
        enable => false,
    }
}
