
define cfdb::instance (
    $type,
    $is_secondary = false,
    
    $memory_weight = 100,
    $cpu_weight = 100,
    $io_weight = 100,
    $target_size = 'auto',
    
    $settings_tune = {},
    $databases = undef,
    
    $iface = $cfdb::iface,
    $port = undef,
    
    $backup = $cfdb::backup,
    $backup_tune = {},
) {
    include stdlib
    include cfnetwork
    include cfsystem
    include cfdb
    
    #---
    $cluster = $title
    $service_name = "cf${type}-${cluster}"
    $user = "${type}_${cluster}"
    $root_dir = "${cfdb::root_dir}/${user}"
    
    if $iface == 'any' {
        $listen = undef
    } elsif defined(Cfnetwork::Iface[$iface]) {
        $iface_addr = pick_default(getparam(Cfnetwork::Iface[$iface], 'address'), undef)
        
        if is_string($iface_addr) {
            $listen = $iface_addr.split('/')[0]
        } else {
            $listen = undef
        }
    } else {
        $listen = $iface
    }
    
    #---
    group { $user:
        ensure => present,
    }
    
    user { $user:
        ensure => present,
        gid => $user,
        home => $root_dir,
        system => true,
        shell => '/bin/bash',
        require => Group[$user],
    }
    
    #---
    $user_dirs = [
        "${root_dir}",
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
    cfsystem_memory_weight { $cluster:
        ensure => present,
        weight => $memory_weight,
        min_mb => 128,
        max_mb => $memory_max,
    }
    
    include "cfdb::${type}"
    include "cfdb::${type}::serverpkg"
    
    cfdb_instance { $cluster:
        ensure => present,
        type => $type,
        cluster => $cluster,
        user => $user,
        is_cluster => getvar("cfdb::${type}::is_cluster"),
        is_secondary => $is_secondary,
        
        memory_weight => $memory_weight,
        cpu_weight => $cpu_weight,
        io_weight => $io_weight,
        target_size => $target_size,
        
        root_dir => $root_dir,
        
        settings_tune => merge(
            $settings_tune,
            { cfdb => merge({
                    'listen' => $listen,
                    'port' => $port,
                }, pick($settings_tune['cfdb'], {}))
            }),
        service_name => $service_name,
        
        require => [
            User[$user],
            File[$user_dirs],
            Class["cfdb::${type}::serverpkg"],
            Cfsystem_memory_weight[$cluster],
        ],
    }
    
    service { $service_name:
        enable => true,
        require => [
            Cfdb_instance[$cluster],
            Cfsystem_flush_config['commit'],
        ]
    }
    
    if $databases {
        if is_array($databases) {
            $databases.each |$db| {
                create_resources(
                    cfdb::database,
                    {
                        "${cluster}/${db}" => {}
                    },
                    {
                        require => [
                            Cfdb_instance[$cluster],
                        ]
                    }
                )
            }
        } elsif is_hash($databases) {
            $databases.each |$db, $cfg| {
                create_resources(
                    cfdb::database,
                    {
                        "${cluster}/${db}" => pick_default($cfg, {})
                    },
                    {
                        require => [
                            Cfdb_instance[$cluster],
                        ]
                    }
                )
            }
        } else {
            fail('$databases must be an array or hash')
        }
    }
    
    #---
    $backup_script = "${root_dir}/bin/cfdb_backup"
    $backup_script_auto ="${backup_script}_auto"
    $backup_dir = "${cfdb::backup_dir}/${user}"
    
    file { $backup_dir:
        ensure => directory,
        owner => $user,
        group => $user,
        mode => '0750',
    }
    
    file { $backup_script:
        mode => '0755',
        content => epp("cfdb/cfdb_backup_${type}.epp", merge({
            backup_dir => $backup_dir,
            root_dir => $root_dir,
            user => $user,
        }, $backup_tune)),
        require => File[$backup_dir],
    }
    
    if $backup == false {
        file { $backup_script_auto:
            ensure => absent,
        }
    } else {
        file { $backup_script_auto:
            ensure => link,
            target => $backup_script,
            require => File[$backup_script],
        }
    }
}