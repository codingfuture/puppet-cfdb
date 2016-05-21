
class cfdb::mysql::arbitratorpkg {
    package { "percona-xtradb-cluster-garbd-3": }
    
    # default instance must not run
    service { 'garbd':
        ensure => stopped,
        enable => false,
    }
}
