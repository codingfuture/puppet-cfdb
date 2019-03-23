#
# Copyright 2016-2019 (c) Andrey Galkin
#


class cfdb::mongodb::arbitratorpkg {
    assert_private()

    include cfdb::mongodb::serverpkg
}
