#
# Copyright 2019 (c) Andrey Galkin
#

class cfdb::redis::arbitratorpkg {
    assert_private()

    include cfdb
    include cfdb::redis

    ensure_resource('package', 'redis-sentinel')
    ensure_resource( service, 'redis-sentinel', {
        ensure   => stopped,
        enable   => false,
        provider => 'systemd',
    })
}
