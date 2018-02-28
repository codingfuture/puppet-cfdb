#
# Copyright 2018 (c) Andrey Galkin
#


class cfdb::elasticsearch::clientpkg {
    assert_private()

    include cfdb
    include cfdb::elasticsearch

    $ver = $cfdb::elasticsearch::version
}
