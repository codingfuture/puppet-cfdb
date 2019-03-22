#
# Copyright 2017-2019 (c) Andrey Galkin
#


define cfdb::mysql::instancebin(
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

    if !$is_arbitrator {
        $mysql_script = "${cfdb::bin_dir}/cfdb_${cluster}_mysql"
        file { $mysql_script:
            mode    => '0755',
            content => epp('cfdb/cfdb_mysql.epp', {
                user => $user,
            }),
            notify  => Cfdb_instance[$cluster],
        }

        file { "${cfdb::bin_dir}/cfdb_${cluster}_mysqladmin":
            mode    => '0755',
            content => epp('cfdb/cfdb_mysqladmin.epp', {
                user => $user,
            }),
            notify  => Cfdb_instance[$cluster],
        }

        file { "${cfdb::bin_dir}/cfdb_${cluster}_sysbench":
            mode    => '0755',
            content => epp('cfdb/cfdb_sysbench.epp', {
                user => $user,
            }),
        }

        # Remove insecure artifacts
        file { "${root_dir}/bin/cfdb_mysql":
            ensure => absent,
        }
        file { "${root_dir}/bin/cfdb_sysbench":
            ensure => absent,
        }

        if $is_cluster {
            $bootstrap_script = "${cfdb::bin_dir}/cfdb_${cluster}_bootstrap"
            file { $bootstrap_script:
                mode    => '0755',
                content => epp('cfdb/cfdb_mysql_bootstrap.epp', {
                    service_name => $service_name,
                    root_dir     => $root_dir,
                })
            }
        }
    }
}
