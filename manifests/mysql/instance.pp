
define cfdb::postgresql::instance (
    $cluster_name,
    $is_secondary,
    $root_dir,
    $settings_tune,
) {
    assert_private()
    
    include cfsystem
    include cfdb::mysql
    include cfdb::mysql::serverpkg
    
    if $is_secondary {
        if !$cfdb::mysql::is_cluster {
            fail('Secondary MySQL instance is supported only in cluster mode')
        }
        
        fail('TODO: support secondary mysql')
    } elsif $databases {
        $databases.each |$db, $cfg| {
            create_resources(
                cfdb::mysql::db,
                {
                    "${cluster_name}@${db}" => merge($cfg, {
                        cluster_name => $cluster_name
                    })
                }
            )
        }
    }
}
