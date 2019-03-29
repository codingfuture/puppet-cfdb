#
# Copyright 2016-2019 (c) Andrey Galkin
#


class cfdb::redis::serverpkg {
    assert_private()

    include cfdb
    include cfdb::redis
    include cfdb::redis::arbitratorpkg

    ensure_packages([
        'redis-server',
        'rdiff-backup',
    ])

    ensure_resource( service, 'redis-server', {
        ensure   => stopped,
        enable   => false,
        provider => 'systemd',
    })
}
