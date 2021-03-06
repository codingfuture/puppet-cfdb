#
# Copyright 2016-2019 (c) Andrey Galkin
#


define cfdb::database (
    String[1]
        $cluster,
    String[1]
        $database,
    Optional[String[1]]
        $password = undef,
    Optional[Hash]
        $roles = undef,
    Array[String[1]]
        $ext = [],
) {
    cfdb_database { $title:
        ensure   => present,
        cluster  => $cluster,
        database => $database,
        ext      => $ext,
    }

    cfdb::role { $title:
        cluster  => $cluster,
        database => $database,
        password => $password,
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
                            }
                        )
                    }
                )
            }
        } else {
            fail('$roles must be a hash')
        }
    }

    # if !defined(Cfdb::Cfdb_instance[$cluster]) {
    #         fail("Cfdb::Cfdb_instance[$cluster] must be defined")
    #     }
    #     
    #     if getparam(Cfdb::Cfdb_instance[$cluster], 'is_secondary') {
    #         fail("Cfdb::Cfdb_instance[$cluster] is defined as secondary - it's not allowed to add DB")
    #     }
}
