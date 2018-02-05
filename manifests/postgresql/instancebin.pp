#
# Copyright 2017-2018 (c) Andrey Galkin
#


define cfdb::postgresql::instancebin(
    String[1] $cluster,
    String[1] $user,
    String[1] $root_dir,
    String[1] $service_name,
    Boolean $is_cluster,
    Boolean $is_arbitrator,
    Boolean $is_primary,
){
    assert_private()

    $psql_script = "${cfdb::bin_dir}/cfdb_${cluster}_psql"
    file { $psql_script:
        mode    => '0755',
        content => epp('cfdb/cfdb_psql.epp', {
            user         => $user,
            service_name => $service_name,
        }),
        notify  => Cfdb_instance[$cluster],
    }
    -> file { "${root_dir}/bin/cfdb_psql":
        ensure => link,
        target => $psql_script,
    }

    if $is_cluster {
        $repmgr_script = "${cfdb::bin_dir}/cfdb_${cluster}_repmgr"
        file { $repmgr_script:
            mode    => '0755',
            content => epp('cfdb/cfdb_repmgr.epp', {
                root_dir     => $root_dir,
                user         => $user,
                service_name => $service_name,
            }),
            notify  => Cfdb_instance[$cluster],
        }
        -> file { "${root_dir}/bin/cfdb_repmgr":
            ensure => link,
            target => $repmgr_script,
        }

        if !$is_arbitrator {
            cfauth::sudoentry { $user:
                command => [
                    "/bin/systemctl start ${service_name}.service",
                    "/bin/systemctl stop ${service_name}.service",
                    "/bin/systemctl restart ${service_name}.service",
                    "/bin/systemctl reload ${service_name}.service",
                ],
            }
            -> Cfdb_instance[$cluster]
        }
    }
}
