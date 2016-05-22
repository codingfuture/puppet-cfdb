
class cfdb::haproxy(
    $memory_weight = 100,
    $memory_max = undef,
    $cpu_weight = 100,
    $io_weight = 100,
    $settings_tune = {},
) {
    include cfdb

    if !defined(Package['haproxy']) {
        package { 'haproxy': }
        service { 'haproxy':
            ensure => stopped,
            enable => false,
        }
    }

    $service_name = 'cfhaproxy'
    $user = $service_name
    $root_dir = "${cfdb::root_dir}/${user}"
    
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
    
    cfsystem_memory_weight { $service_name:
        ensure => present,
        weight => $memory_weight,
        min_mb => 16,
        max_mb => $memory_max,
    }
    
    cfdb_haproxy { $title:
        ensure         => present,
        memory_weight  => $memory_weight,
        cpu_weight     => $cpu_weight,
        io_weight      => $io_weight,
        root_dir       => $root_dir,
        settings_tune  => $settings_tune,
        service_name   => $service_name,
    }
}
