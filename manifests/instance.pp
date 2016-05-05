
define cfdb::instance (
    $type,
    $is_secondary = false,
    
    $memory_weight = 100,
    $cpu_weight = 100,
    $io_weight = 100,
    $target_size = 'auto',
    
    $settings_tune = {},
) {
    include stdlib
    include cfsystem
    include cfdb
    
    #---
    $cluster_name = $title
    $service_name = "${type}-${cluster_name}"
    $user = "${type}_${cluster_name}"
    $root_dir = "${cfdb::root_dir}/${user}"
    
    group { $user:
        ensure => present,
    }
    
    user { $user:
        ensure => present,
        gid => $user,
        home => $root_dir,
        managehome => true,
        system => true,
        shell => '/bin/bash',
        require => Group[$user],
    }
    
    #---
    $user_dirs = [
        "${root_dir}/bin",
        "${root_dir}/conf",
        "${root_dir}/var",
        "${root_dir}/tmp",
    ]
    file { $user_dirs:
        ensure => directory,
        owner => $user,
        group => $user,
        mode => '0750',
    }
    
    #---
    cfsystem_memory_weight { $cluster_name:
        ensure => present,
        weight => $memory_weight,
        min_mb => 128,
        max_mb => $memory_max,
    }
    
    include "cfdb::${type}"
    include "cfdb::${type}::serverpkg"
    
    cfdb_instance { $cluster_name:
        ensure => present,
        type => $type,
        cluster_name => $cluster_name,
        user => $user,
        is_cluster => getvar("cfdb::${type}::is_cluster"),
        is_secondary => $is_secondary,
        
        memory_weight => $memory_weight,
        cpu_weight => $cpu_weight,
        io_weight => $io_weight,
        target_size => $target_size,
        
        root_dir => $root_dir,
        
        settings_tune => $settings_tune,
        service_name => $service_name,
        
        require => [
            User[$user],
            File[$user_dirs],
            Class["cfdb::${type}::serverpkg"],
            Cfsystem_memory_weight[$cluster_name],
        ],
    }
    
    service { $service_name:
        enable => true,
        require => [
            Cfdb_instance[$cluster_name],
            Cfsystem_flush_config['commit'],
        ]
    }
    
    if $databases {
        $databases.each |$db, $cfg| {
            create_resources(
                cfdb::db,
                {
                    "${cluster_name}/${db}" => pick_default($cfg, {})
                },
                {
                    require => [
                        Cfdb_instance[$cluster_name],
                    ]
                }
            )
        }
    }
}