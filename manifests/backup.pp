#
# Copyright 2016-2019 (c) Andrey Galkin
#


class cfdb::backup {
    assert_private()
    include cfsystem::custombin
    include cfbackup

    $root_dir = "${cfbackup::root_dir}/cfdb"

    file { $root_dir:
        ensure => directory,
        mode   => '0511',
    }

    # cleanup legacy implementation
    $backup_all_script = "${cfsystem::custombin::bin_dir}/cfdb_backup_all"

    file { $backup_all_script:
        ensure => absent,
    }

    cron { 'cfdb_backup_all':
        ensure => absent,
    }
}
