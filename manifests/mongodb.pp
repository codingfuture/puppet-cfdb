#
# Copyright 2016-2019 (c) Andrey Galkin
#

class cfdb::mongodb (
    String[1]
        $version = $cfdb::mongodb::defaults::version,
) inherits cfdb::mongodb::defaults {
    #assert_private()

    include stdlib
    include cfdb
    # TODO: refactor Percona APT repo some day
    include cfdb::mysql

    $latest = $cfdb::mongodb::defaults::latest
    $actual_version = $version
    $is_cluster = true
    $is_unidb = false

    if $actual_version != $latest {
        cf_notify { "\$cfdb::mongodb::version ${version} is not the latest ${latest}":
            loglevel => warning,
        }
    }
}
