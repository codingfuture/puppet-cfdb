
class cfdb (
    $instances = {},
    $access = {},
    $iface = 'any',
    $root_dir = '/db',
    $max_connections_default = 10,
    
    $backup = true,
    $backup_cron = {},
    $backup_dir = '/mnt/backup',
) {
    include cfsystem::custombin
    
    file { [$root_dir, $backup_dir]:
        ensure => directory,
        mode => '0555',
    }
    
    create_resources(cfdb::instance, $instances)
    create_resources(cfdb::access, $access)
    
    #---
    $backup_all_script = "${cfsystem::custombin::bin_dir}/cfdb_backup_all"
    
    file {$backup_all_script:
        mode => '0700',
        content => epp('cfdb/cfdb_backup_all.epp'),
    }
    
    create_resources(cron, $backup_cron, {
        command => $backup_all_script,
        hour => 3,
        minute => 10,
    })
}
