
class cfdb::mysql (
    $is_cluster = false,
    $percona_apt_repo = 'http://repo.percona.com/apt',
    $version = '5.7',
    $cluster_version = '5.6',
) {
    assert_private()
    
    include stdlib
    include cfdb
    
    if  $is_cluster {
        $actual_version = $cluster_version
    } else {
        $actual_version = $version
    }
    
    class { 'cfdb::mysql::perconaapt':
        stage => setup
    }
}
