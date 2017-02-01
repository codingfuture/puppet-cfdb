#
# Copyright 2016-2017 (c) Andrey Galkin
#


class cfdb::mysql (
    Boolean
        $is_cluster = false,
    String[1]
        $percona_apt_repo = 'http://repo.percona.com/apt',
    String[1]
        $version = '5.7',
    String[1]
        $cluster_version = '5.7',
) {
    #assert_private()

    include stdlib
    include cfdb

    if $is_cluster {
        $actual_version = $cluster_version
    } else {
        $actual_version = $version
    }

    class { 'cfdb::mysql::perconaapt':
        stage => setup
    }
}
