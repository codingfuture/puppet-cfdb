#
# Copyright 2016-2019 (c) Andrey Galkin
#


class cfdb::mongodb::clientpkg {
    assert_private()

    include cfdb::mongodb

    $ver = $cfdb::mongodb::actual_version

    $ver_nodot = regsubst($ver, '\.', '', 'G')
    package { "percona-server-mongodb-${ver_nodot}-shell": }

    # required for healthcheck script
    ensure_resource('package', 'python-pymongo', {})
    ensure_resource('package', 'python-pymongo-ext', {})
}
