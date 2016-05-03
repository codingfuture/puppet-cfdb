
define cfdb::postgresql::instance (
    $cluster_name,
    $is_secondary,
    $root_dir,
    $settings_tune,
) {
    assert_private()
    
    include cfdb::postgresql
    include cfdb::postgresql::serverpkg
    
    if $is_secondary {
        if !$cfdb::postgresql::is_cluster {
            fail('Secondary PostgreSQL instance is supported only in cluster mode')
        }
        
        fail('TODO: support secondary PostgreSQL')
    }
}
