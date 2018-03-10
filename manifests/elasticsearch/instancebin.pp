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
    Hash $settings_tune,
){
    assert_private()

    $conf_dir = "${root_dir}/conf"

    #---

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

    #---

    file { "${conf_dir}/ingest-geoip":
        owner   => $user,
        mode    => '0750',
        source  => '/etc/elasticsearch/ingest-geoip',
        recurse => true,
    }

    #---

    include cfdb::elasticsearch::curator

    file { "${cfdb::bin_dir}/cfdb_${cluster}_curator":
        mode    => '0755',
        content => epp('cfdb/cfdb_curator.epp', {
            user => $user,
        }),
    }

    file { "${root_dir}/.curator":
        ensure => directory,
        owner  => $user,
        group  => $user,
        mode   => '0750',
    }
    file { "${root_dir}/.curator/curator.yml":
        owner   => $user,
        group   => $user,
        mode    => '0640',
        content => to_yaml({
            client => {
                hosts => [ pick($settings_tune['cfdb']['listen'], '127.0.0.1') ],
                port  => $settings_tune['cfdb']['port'],
            }
        }),
    }
}
