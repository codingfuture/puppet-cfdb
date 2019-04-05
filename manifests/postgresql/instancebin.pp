#
# Copyright 2017-2019 (c) Andrey Galkin
#


define cfdb::postgresql::instancebin(
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

    # a workaround for ignorant PostgreSQL devs
    #---
    cfnetwork::service_port { "local:alludp:${cluster}-stats": }
    cfnetwork::client_port { "local:alludp:${cluster}-stats":
        user => $user,
    }
    #---

    # psql
    #---
    $psql_script = "${cfdb::bin_dir}/cfdb_${cluster}_psql"
    file { $psql_script:
        mode    => '0755',
        content => epp('cfdb/cfdb_psql.epp', {
            user         => $user,
            service_name => $service_name,
            version      => $version,
        }),
        notify  => Cfdb_instance[$cluster],
    }
    -> file { "${root_dir}/bin/cfdb_psql":
        ensure => link,
        target => $psql_script,
    }

    # vacuumdb
    #---
    $vacuumdb_script = "${cfdb::bin_dir}/cfdb_${cluster}_vacuumdb"
    file { $vacuumdb_script:
        mode    => '0755',
        content => epp('cfdb/cfdb_vacuumdb.epp', {
            user         => $user,
            service_name => $service_name,
            version      => $version,
        }),
        notify  => Cfdb_instance[$cluster],
    }
    -> file { "${root_dir}/bin/cfdb_vacuumdb":
        ensure => link,
        target => $vacuumdb_script,
    }

    if $is_cluster {
        # repmgr
        #---
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

        # SSL
        #---
        file { "${root_dir}/.postgresql":
            ensure => directory,
            mode   => '0750',
            owner  => $user,
        }
        file { "${root_dir}/.postgresql/root.crt":
            ensure => link,
            target => '../pki/puppet/ca.crt',
            mode   => '0750',
            owner  => $user,
        }
        file { "${root_dir}/.postgresql/postgresql.crt":
            ensure => link,
            target => '../pki/puppet/local.crt',
            mode   => '0750',
            owner  => $user,
        }
        file { "${root_dir}/.postgresql/postgresql.key":
            ensure => link,
            target => '../pki/puppet/local.key',
            mode   => '0750',
            owner  => $user,
        }
        #---

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
