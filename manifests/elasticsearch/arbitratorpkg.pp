#
# Copyright 2018-2019 (c) Andrey Galkin
#

class cfdb::elasticsearch::arbitratorpkg {
    assert_private()

    include cfdb
    include cfdb::elasticsearch
}
