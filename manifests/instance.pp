
define cfdb::instance (
    $type,
    $is_secondary = false,
    $bootstrap_node = false,
    
    $memory_weight = 100,
    $memory_max = undef,
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
        
        if $iface_addr and is_string($iface_addr) {
            $listen = $iface_addr.split('/')[0]
        } else {
            $listen = undef
        }
    } else {
        $listen = undef
    }
    
    #---
    group { $user:
        ensure => present,
    }
    
    user { $user:
        ensure  => present,
        gid     => $user,
        home    => $root_dir,
        system  => true,
        shell   => '/bin/bash',
        require => Group[$user],
    }
    
    #---
    $user_dirs = [
        $root_dir,
        "${root_dir}/bin",
        "${root_dir}/conf",
        "${root_dir}/var",
        "${root_dir}/tmp",
    ]
    file { $user_dirs:
        ensure => directory,
        owner  => $user,
        group  => $user,
        mode   => '0750',
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
    
    #---
    if getvar("cfdb::${type}::is_cluster") {
        $cluster_facts_all = query_facts(
            "cfdb.${cluster}.present=true",
            ['cfdb']
        )
        
        if empty($cluster_facts_all) {
            $cluster_addr = []
        } else {
            $cluster_addr = ($cluster_facts_all.map |$host, $cfdb_facts| {
                $cluster_fact = $cfdb_facts['cfdb'][$cluster]
                
                if $type != $cluster_fact['type'] {
                    fail("Type of ${cluster} on ${host} mismatch ${type}: ${cluster_fact}")
                }
                
                $peer_addr = pick($cluster_fact['host'], $host)
                $peer_port = $cluster_fact['port']
                
                if $host == $::trusted['certname'] {
                    undef
                } else {
                    if $type == 'mysql' {
                        # TODO: wrap into some functions
                        $galera_port = $peer_port + 100
                        $sst_port = $peer_port + 200
                        $ist_port = $peer_port + 300
                        
                        if !$peer_addr or !$peer_port {
                            fail("Invalid host/port for ${host}: ${cluster_fact}")
                        }
                        
                        $host_under = regsubst($host, '\.', '_', 'G')
                    
                        cfnetwork::describe_service { "cfdb_${cluster}_peer_${host_under}":
                            server => "tcp/${peer_port}",
                        }
                        cfnetwork::describe_service { "cfdb_${cluster}_galera_${host_under}":
                            server => "tcp/${galera_port}",
                        }
                        cfnetwork::describe_service { "cfdb_${cluster}_sst_${host_under}":
                            server => "tcp/${sst_port}",
                        }
                        cfnetwork::describe_service { "cfdb_${cluster}_ist_${host_under}":
                            server => "tcp/${ist_port}",
                        }
                        
                        cfnetwork::client_port { "${iface}:cfdb_${cluster}_peer_${host_under}":
                            dst  => $peer_addr,
                            user => $user,
                        }
                        cfnetwork::client_port { "${iface}:cfdb_${cluster}_galera_${host_under}":
                            dst  => $peer_addr,
                            user => $user,
                        }
                        cfnetwork::client_port { "${iface}:cfdb_${cluster}_sst_${host_under}":
                            dst  => $peer_addr,
                            user => $user,
                        }
                        cfnetwork::client_port { "${iface}:cfdb_${cluster}_ist_${host_under}":
                            dst  => $peer_addr,
                            user => $user,
                        }
                    }
                    
                    
                    "${peer_addr}:${port}"
                }
            }).filter |$v| { $v != undef }
        }
        
        if $type == 'mysql' {
            if !$port {
                fail('Cluster requires excplicit port')
            }
            
            # TODO: wrap into some functions
            $galera_port = $port + 100
            $sst_port = $port + 200
            $ist_port = $port + 300
            
            $peer_addr = $cluster_addr.map |$v| {
                $v.split(':')[0]
            }
            
            cfnetwork::describe_service { "cfdb_${cluster}_peer":
                server => "tcp/${port}",
            }
            cfnetwork::describe_service { "cfdb_${cluster}_galera":
                server => "tcp/${galera_port}",
            }
            cfnetwork::describe_service { "cfdb_${cluster}_sst":
                server => "tcp/${sst_port}",
            }
            cfnetwork::describe_service { "cfdb_${cluster}_ist":
                server => "tcp/${ist_port}",
            }
            
            if size($peer_addr) > 0 {
                cfnetwork::service_port { "${iface}:cfdb_${cluster}_peer":
                    src => $peer_addr,
                }
                cfnetwork::service_port { "${iface}:cfdb_${cluster}_galera":
                    src => $peer_addr,
                }
                cfnetwork::service_port { "${iface}:cfdb_${cluster}_sst":
                    src => $peer_addr,
                }
                cfnetwork::service_port { "${iface}:cfdb_${cluster}_ist":
                    src => $peer_addr,
                }
            }
        }
    } else {
        $cluster_addr = undef
    }
    #---
    
    cfdb_instance { $cluster:
        ensure         => present,
        type           => $type,
        cluster        => $cluster,
        user           => $user,
        is_cluster     => getvar("cfdb::${type}::is_cluster"),
        is_secondary   => $is_secondary,
        bootstrap_node => $bootstrap_node,
        
        memory_weight  => $memory_weight,
        cpu_weight     => $cpu_weight,
        io_weight      => $io_weight,
        target_size    => $target_size,
        
        root_dir       => $root_dir,
        
        settings_tune  => merge(
            $settings_tune,
            {
                cfdb => merge(
                    {
                        'listen' => $listen,
                        'port'   => $port,
                    },
                    pick($settings_tune['cfdb'], {})
                )
            }
        ),
        service_name   => $service_name,
        cluster_addr   => $cluster_addr,
        
        require        => [
            User[$user],
            File[$user_dirs],
            Class["cfdb::${type}::serverpkg"],
            Cfsystem_memory_weight[$cluster],
        ],
    }
    
    service { $service_name:
        enable  => true,
        require => [
            Cfdb_instance[$cluster],
            Cfsystem_flush_config['commit'],
        ]
    }
    
    if $databases {
        if $is_secondary {
            fail("It's not allowed to defined databases on secondary server")
        }
        
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
    $restore_script = "${root_dir}/bin/cfdb_restore"
    $backup_script_auto ="${backup_script}_auto"
    $backup_dir = "${cfdb::backup_dir}/${user}"
    
    file { $backup_dir:
        ensure => directory,
        owner  => $user,
        group  => $user,
        mode   => '0750',
    }
    
    file { $backup_script:
        mode    => '0755',
        content => epp("cfdb/cfdb_backup_${type}.epp", merge({
            backup_dir => $backup_dir,
            root_dir   => $root_dir,
            user       => $user,
        }, $backup_tune)),
        require => File[$backup_dir],
        notify  => Cfdb_instance[$cluster],
    }
    
    file { $restore_script:
        mode    => '0755',
        content => epp("cfdb/cfdb_restore_${type}.epp", {
            backup_dir   => $backup_dir,
            root_dir     => $root_dir,
            user         => $user,
            service_name => $service_name,
        }),
        require => File[$backup_dir],
        notify  => Cfdb_instance[$cluster],
    }
    
    if $backup == false {
        file { $backup_script_auto:
            ensure => absent,
        }
    } else {
        file { $backup_script_auto:
            ensure  => link,
            target  => $backup_script,
            require => File[$backup_script],
        }
    }
    
    #---
    case $type {
        'mysql': {
            file { "${root_dir}/bin/cfdb_sysbench":
                mode    => '0755',
                content => epp('cfdb/cfdb_sysbench.epp', {
                    user => $user,
                }),
            }
        }
    }
}