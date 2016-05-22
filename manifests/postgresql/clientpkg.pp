
class cfdb::postgresql::clientpkg {
    assert_private()
    
    include cfdb
    include cfdb::postgresql
    
    $ver = $cfdb::postgresql::version

    package { "postgresql-client-${ver}": }
}
