#
# Copyright 2016-2017 (c) Andrey Galkin
#


class cfdb (
    Hash
        $instances = {},
    Hash
        $access = {},
    String[1]
        $iface = 'any',
    String[1]
        $root_dir = '/db',
    Integer[1]
        $max_connections_default = 10,
    Boolean
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

    #---
    include cfsystem
    include cfsystem::custombin
    $restart_pending_script = "${cfsystem::custombin::bin_dir}/cfdb_restart_pending"

    file { $restart_pending_script:
        mode    => '0700',
        content => epp('cfdb/cfdb_restart_pending.sh.epp'),
    }

}
