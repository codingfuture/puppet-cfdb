#
# Copyright 2016-2018 (c) Andrey Galkin
#


class cfdb::backup(
    Hash
        $cron = {},
    String[1]
        $root_dir = '/mnt/backup',
) {
    assert_private()
    include cfsystem::custombin

    file { $root_dir:
        ensure => directory,
        mode   => '0555',
    }

    #---
    $backup_all_script = "${cfsystem::custombin::bin_dir}/cfdb_backup_all"

    file { $backup_all_script:
        mode    => '0700',
        content => epp('cfdb/cfdb_backup_all.epp'),
    }

    create_resources(
        cron,
        {
            cfdb_backup_all => $cron,
        },
        {
            command => $backup_all_script,
            hour => 3,
            minute => 10,
        }
    )
}
