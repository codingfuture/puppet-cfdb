#
# Copyright 2016-2017 (c) Andrey Galkin
#


class cfdb::postgresql::clientpkg {
    assert_private()

    include cfdb
    include cfdb::postgresql

    $ver = $cfdb::postgresql::version

    ensure_resource('package', "postgresql-client-${ver}", {})

    # required for healthcheck script
    ensure_resource('package', 'python-psycopg2', {})
}
