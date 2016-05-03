
class cfdb::instance (
    $cluster_name = $title,
    $type,
    $is_secondary,
    
    $memory_weight,
    $cpu_weight,
    $io_weight,
    
    $root_dir,
    settings_tune = $settings_tune,
) {
    include stdlib
    include cfsystem
    include cfdb
    
    #---
    $user = "${type}_${cluster_name}"
    $home_dir = "${cfdb::root_dir}/${user}"
    
    group { $user:
        ensure => present,
    }
    
    user { $user:
        ensure => present,
        gid => $user,
        home => $home_dir,
        managehome => true,
        system => true,
        shell => '/bin/bash',
        require => Group[$user],
    }
    
    #---
    $user_dirs = [
        "${home_dir}/bin",
        "${home_dir}/conf",
        "${home_dir}/data",
        "${home_dir}/var",
        "${home_dir}/tmp",
    ]
    file { $user_dirs:
        ensure => present,
        owner => $user,
        group => $user,
        mode => '0750',
    }
    
    #---
    cfsystem_memory_weight { $title:
        ensure => present,
        weight => $memory_weight,
        min_mb => 128,
        max_mb => $memory_max,
    }
    
    cfdb_instance { $title:
        type => $type,
        cluster_name => $cluster_name,
        is_cluster => $cfdb::$type::is_cluster,
        is_secondary => $is_secondary,
        
        memory_weight => $memory_weight,
        cpu_weight => $cpu_weight,
        io_weight => $io_weight,
        
        root_dir => $root_dir,
        
        settings_tune => $settings_tune,
        
        require => [
            User[$user],
            File[$user_dirs],
        ],
    }
    

    cfdb::$type::instance { $title:
        cluster_name => $cluster_name,
        is_secondary => $is_secondary,
        root_dir => $root_dir,
        settings_tune => $settings_tune,
    }
    
    if $databases {
        $databases.each |$db, $cfg| {
            create_resources(
                cfdb::$type::db,
                {
                    "${cluster_name}/${db}" => merge($cfg, {
                        db_name => $db,
                        cluster_name => $cluster_name
                    })
                }
            )
        }
    }
}