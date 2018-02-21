#
# Copyright 2018 (c) Andrey Galkin
#


define cfdb::elasticsearch::instancebin(
    String[1] $cluster,
    String[1] $user,
    String[1] $root_dir,
    String[1] $service_name,
    String[1] $version,
    Boolean $is_cluster,
    Boolean $is_arbitrator,
    Boolean $is_primary,
){
    assert_private()

    $conf_dir = "${root_dir}/conf"

    file { "${conf_dir}/log4j2.properties":
        ensure  => present,
        owner   => $user,
        mode    => '0640',
        content => file( 'cfdb/log4j2.properties' ),
    }

    file { "${conf_dir}/jvm.options":
        ensure  => present,
        owner   => $user,
        mode    => '0640',
        content => '-Dlog4j2.disable.jmx=true',
    }

    file { "${cfdb::bin_dir}/cfdb_${cluster}_curl":
        mode    => '0755',
        content => epp('cfdb/cfdb_curl.epp', {
            user => $user,
        }),
    }

    file { "${root_dir}/bin/cfdb_curl":
        owner   => $user,
        mode    => '0750',
        content => '#!/bin/false',
        replace => false,
    }
}
