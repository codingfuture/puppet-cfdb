#
# Copyright 2016-2017 (c) Andrey Galkin
#


class cfdb::postgresql (
    $version = '9.6',
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
