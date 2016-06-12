
class cfdb::postgresql::clientpkg {
    assert_private()
    
    include cfdb
    include cfdb::postgresql
    
    $ver = $cfdb::postgresql::version

    ensure_resource('package', "postgresql-client-${ver}", {})
    
    # required for healthcheck script
    ensure_resource('package', 'python-psycopg2', {})
}
