#
# Copyright 2016-2017 (c) Andrey Galkin
#


class cfdb (
    $instances = {},
    $access = {},
    $iface = 'any',
    $root_dir = '/db',
    $max_connections_default = 10,
    $backup = true,
) {
    # global healthcheck db/role names
    $healthcheck = 'cfdbhealth'

    $bin_dir = "${root_dir}/bin"

    file { $root_dir:
        ensure => directory,
        mode   => '0555',
    }

    file { $bin_dir:
        ensure => directory,
        mode   => '0555',
        purge  => true,
    }

    create_resources(cfdb::instance, $instances)
    create_resources(cfdb::access, $access)
}
