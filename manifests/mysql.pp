#
# Copyright 2016-2017 (c) Andrey Galkin
#


class cfdb::mysql (
    $is_cluster = false,
    $percona_apt_repo = 'http://repo.percona.com/apt',
    $version = '5.7',
    $cluster_version = '5.7',
) {
    #assert_private()

    include stdlib
    include cfdb

    if $is_cluster {
        $actual_version = $cluster_version
    } else {
        if $::os['name'] != 'Ubuntu' {
            $actual_version = $version
        } else {
            $actual_version = '5.6'
        }
    }

    class { 'cfdb::mysql::perconaapt':
        stage => setup
    }
}
