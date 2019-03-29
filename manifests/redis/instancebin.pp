#
# Copyright 2019 (c) Andrey Galkin
#


define cfdb::redis::instancebin(
    String[1] $cluster,
    String[1] $user,
    String[1] $root_dir,
    String[1] $service_name,
    String[1] $version,
    Boolean $is_cluster,
    Boolean $is_arbitrator,
    Boolean $is_primary,
    Hash $settings_tune,
    Hash $sched_actions,
){
    assert_private()

    $redis_script = "${cfdb::bin_dir}/cfdb_${cluster}_rediscli"
    file { $redis_script:
        mode    => '0755',
        content => epp('cfdb/cfdb_rediscli.epp', {
            user         => $user,
            service_name => $service_name,
            sentinel     => false,
        }),
        notify  => Cfdb_instance[$cluster],
    }

    if $is_cluster {
        $sentinel_script = "${cfdb::bin_dir}/cfdb_${cluster}_sentinelcli"
        file { $sentinel_script:
            mode    => '0755',
            content => epp('cfdb/cfdb_rediscli.epp', {
                user         => $user,
                service_name => $service_name,
                sentinel     => true,
            }),
            notify  => Cfdb_instance[$cluster],
        }
    }
}
