#
# Copyright 2016-2019 (c) Andrey Galkin
#


class cfdb::mongodb::serverpkg {
    assert_private()

    include cfdb
    include cfdb::mongodb

    $ver = $cfdb::mongodb::actual_version

    $ver_nodot = regsubst($ver, '\.', '', 'G')
    package { "percona-server-mongodb-${ver_nodot}": }

    # default instance must not run
    -> service { 'mongod':
        ensure   => stopped,
        enable   => mask,
        provider => 'systemd',
    }
}
