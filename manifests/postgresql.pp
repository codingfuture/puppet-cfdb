#
# Copyright 2016-2017 (c) Andrey Galkin
#


class cfdb::postgresql (
    String[1]
        $version = '9.6',
    Boolean
        $default_extensions = true,
    Array[String[1]]
        $extensions = [],
    Array[String[1]]
        $extensions2 = [],
    String[1]
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
