class cfdb::postgresql::arbitratorpkg {
    assert_private()
    
    include cfdb
    include cfdb::postgresql
    
    ensure_resource('package', 'repmgr')
    ensure_resource( service, 'repmgrd', {
        ensure => stopped,
        enable => false,
    })
    
    fail("There is an open repmgr issue #186: https://github.com/2ndQuadrant/repmgr/issues/186
          PostgreSQL witness server is not supported yet")
}