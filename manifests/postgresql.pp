
class cfdb::postgresql (
    $is_cluster = false,
    $version = '9.4',
    $default_extensions = true,
    $extensions = [],
    $apt_repo = 'http://apt.postgresql.org/pub/repos/apt/',
) {
    include stdlib
    include cfdb
    
    $actual_version = $version
    
    class { 'cfdb::postgresql::aptrepo':
        stage => setup
    }
    
    if $is_cluster {
        fail('is_cluster is not supported')
    }
}
