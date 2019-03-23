#
# Copyright 2017-2019 (c) Andrey Galkin
#


define cfdb::mongodb::instancebin(
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

    $mongo_script = "${cfdb::bin_dir}/cfdb_${cluster}_mongo"
    file { $mongo_script:
        mode    => '0755',
        content => epp('cfdb/cfdb_mongo.epp', {
            user => $user,
        }),
        notify  => Cfdb_instance[$cluster],
    }
}
