
class cfdb::mysql::arbitratorpkg {
    assert_private()
    
    package { 'percona-xtradb-cluster-garbd-3': }
    
    # default instance must not run
    service { 'garbd':
        ensure => stopped,
        enable => false,
    }
}
