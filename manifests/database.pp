
define cfdb::database (
    $roles = undef
) {
    $title_split = $title.split('/')
    $cluster = $title_split[0]
    $database = $title_split[1]
    
    cfdb_database { $title:
        ensure => present,
        cluster => $cluster,
        database => $database,
    }
    
    cfdb::role { $title:
        cluster => $cluster,
        database => $database,
    }
    
    if $roles {
        if is_hash($roles) {
            $roles.each |$subname, $cfg| {
                create_resources(
                    cfdb::role,
                    {
                        "${cluster}/${database}${subname}" => merge(
                            pick_default($cfg, {}),
                            {
                                cluster => $cluster,
                                database => $database,
                                subname => $subname,
                                require => [
                                    Cfdb_instance[$cluster],
                                ]
                            }
                        )
                    }
                )
            }
        } else {
            fail('$roles must be a hash')
        }
    }
    
}
