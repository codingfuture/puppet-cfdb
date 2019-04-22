#
# Copyright 2019 (c) Andrey Galkin
#


class cfdb::redis::clientpkg {
    assert_private()

    include cfdb
    include cfdb::redis

    # required for healthcheck script
    ensure_packages(['python-redis', 'redis-tools'])
}
