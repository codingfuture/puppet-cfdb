#
# Copyright 2016-2018 (c) Andrey Galkin
#


define cfdb::require_endpoint(
    String[1] $cluster,
    String[1] $host,
    String[1] $source,
    Integer[0] $maxconn,
    Boolean $secure,
) {
    assert_private()
}
