
class cfdb::mysql::serverpkg {
    assert_private()
    
    include cfdb
    include cfdb::mysql
        
    if $cfdb::mysql::is_cluster {
        $ver = $cfdb::mysql::cluster_version
        $ver_nodot = regsubst($ver, '\.', '', 'G')
        package { "percona-xtradb-cluster-${ver_nodot}": }
        $xtrabackup_ver = '22'
    } else {
        $ver = $cfdb::mysql::version
        package { "percona-server-server-${ver}": }
        
        if versioncmp($ver, '5.7') >= 0 {
            $xtrabackup_ver = '24'
        } else {
            $xtrabackup_ver = '22'
        }
    }
    
    package { "percona-xtrabackup-${xtrabackup_ver}": }
    package { "qpress": }

    # default instance must not run
    service { 'mysql':
        ensure => stopped,
        enable => false,
    }
}
