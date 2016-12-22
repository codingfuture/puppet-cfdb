class cfdb::postgresql::arbitratorpkg {
    assert_private()
    
    include cfdb
    include cfdb::postgresql
    
    ensure_resource('package', 'repmgr')
    ensure_resource( service, 'repmgrd', {
        ensure => stopped,
        enable => false,
    })
}