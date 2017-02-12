#
# Copyright 2016-2017 (c) Andrey Galkin
#

class cfdb::postgresql (
    String[1]
        $version = $cfdb::postgresql::defaults::version,
    Boolean
        $default_extensions = true,
    Array[String[1]]
        $extensions = [],
    Array[String[1]]
        $extensions2 = [],
    String[1]
        $apt_repo = 'http://apt.postgresql.org/pub/repos/apt/',
) inherits cfdb::postgresql::defaults {
    #assert_private()

    include stdlib
    include cfdb

    $latest = $cfdb::postgresql::defaults::latest
    $actual_version = $version
    $is_cluster = true

    class { 'cfdb::postgresql::aptrepo':
        stage => setup
    }

    if $version != $latest {
        notify { "\$cfdb::postgresql::version ${version} is not the latest ${latest}":
            loglevel => warning,
        }
    }
}
