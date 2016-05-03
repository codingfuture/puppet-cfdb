
class cfdb::mysql (
    $is_cluster = false,
    $percona_apt_repo = 'http://repo.percona.com/apt',
    $version = '5.7',
    $cluster_version = '5.6',
) {
    include stdlib
    include cfdb
    
    class { 'cfdb::mysql::perconaapt':
        stage => setup
    }
}
