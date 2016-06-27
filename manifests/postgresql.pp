
class cfdb::postgresql (
    $version = '9.5',
    $default_extensions = true,
    $extensions = [],
    $extensions2 = [],
    $apt_repo = 'http://apt.postgresql.org/pub/repos/apt/',
) {
    #assert_private()
    
    include stdlib
    include cfdb
    
    $actual_version = $version
    $is_cluster = true
    
    class { 'cfdb::postgresql::aptrepo':
        stage => setup
    }
}
