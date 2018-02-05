#
# Copyright 2016-2018 (c) Andrey Galkin
#


class cfdb::haproxy(
    Integer[1]
        $memory_weight = 1,
    Optional[Integer[1]]
        $memory_max = undef,
    Cfsystem::CpuWeight
        $cpu_weight = 100,
    Cfsystem::IoWeight
        $io_weight = 100,

    Hash[String[1], Any]
        $settings_tune = {},
) {
    assert_private()
    include cfdb
    include cfsystem::haproxy

    $service_name = 'cfdbhaproxy'
    $user = $service_name
    $root_dir = "${cfdb::root_dir}/${user}"
    $bin_dir = "${root_dir}/bin"
    $conf_dir = "${root_dir}/conf"
    $tmp_dir = "${root_dir}/tmp"
    $dh_params = "${root_dir}/pki/dh.pem"
    $openssl = '/usr/bin/openssl'

    group { $user:
        ensure => present,
    }

    user { $user:
        ensure  => present,
        gid     => $user,
        home    => $root_dir,
        system  => true,
        shell   => '/bin/sh',
        require => Group[$user],
    }

    # Required for dhparam
    require cfsystem::randomfeed

    file { [$root_dir, $bin_dir, $conf_dir, $tmp_dir]:
        ensure => directory,
        owner  => $user,
        group  => $user,
        mode   => '0750',
    }
    -> cfsystem::puppetpki { $user: }
    -> exec {'Generating CFDB HAProxy Diffie-Hellman params...':
        command  => '/bin/true',
        creates  => $dh_params,
        loglevel => 'warning',
    }
    ~> exec { 'cfdbhaproxy_dhparam':
        command     => "${openssl} dhparam -out ${dh_params} -rand /dev/urandom 2048",
        refreshonly => true,
    }


    cfsystem_memory_weight { $service_name:
        ensure => present,
        weight => $memory_weight,
        min_mb => 16,
        max_mb => $memory_max,
    }
    -> cfdb_haproxy { $service_name:
        ensure        => present,
        memory_weight => $memory_weight,
        cpu_weight    => $cpu_weight,
        io_weight     => $io_weight,
        root_dir      => $root_dir,
        settings_tune => pick($settings_tune, {}),
        service_name  => $service_name,
        require       => [
            Package[$cfsystem::haproxy::package_name],
            File[$root_dir],
            User[$user],
            Cfsystem::Puppetpki[$user],
            Exec['cfdbhaproxy_dhparam'],
        ],
    }

    # service { $service_name:
    #         ensure   => running,
    #         enable   => true,
    #         provider => 'systemd',
    #         require  => [
    #             Package['haproxy'],
    #             Cfsystem_flush_config['commit']
    #         ]
    #     }

    #---
    ensure_resource('package', 'hatop', {})
    file { "${cfdb::bin_dir}/cfdb_hatop":
        mode    => '0555',
        content => [
            '#!/bin/dash',
            "/usr/bin/hatop -s /run/${service_name}/stats.sock"
        ].join("\n"),
    }
}
