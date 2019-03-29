#
# Copyright 2019 (c) Andrey Galkin
#

class cfdb::redis inherits cfdb::redis::defaults {
    #assert_private()

    $actual_version = '*'
    $is_cluster = true
    $is_unidb = true
}
