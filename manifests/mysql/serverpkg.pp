
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
        $xtrabackup_ver = '24'
        package { "percona-server-server-${ver}": }
        package { "percona-xtrabackup-${xtrabackup_ver}": }
    }
    
    package { 'qpress': }
    package { 'percona-toolkit': }

    # default instance must not run
    service { 'mysql':
        ensure => stopped,
        enable => false,
    }
}
