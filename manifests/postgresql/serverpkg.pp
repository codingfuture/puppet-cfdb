
class cfdb::postgresql::serverpkg {
    assert_private()
    
    include cfdb
    include cfdb::postgresql
    
    $ver = $cfdb::postgresql::version

    package { "postgresql-${ver}": }
    
    $cfdb::postgresql::extensions.each |$ext| {
        package { "postgresql-${ver}-${ext}": }
    }
    
    case $ver {
        default: {
            $postgis_ver = '2.2'
        }
    }
    
    if $cfdb::postgresql::default_extensions {
        [
            'asn1oid',
            'debversion',
            'ip4r',
            'partman',
            'pgespresso',
            'pgextwlist',
            'pgmp',
            'pgrouting',
            'pllua',
            'plproxy',
            'plr',
            'plv8',
            "postgis-${postgis_ver}",
            'postgis-scripts',
            'powa',
            'prefix',
            'preprepare',
            'repack',
            'repmgr',
        ].each |$ext| {
            package { "postgresql-${ver}-${ext}": }
        }
        
        [
            'contrib',
            'plperl',
            'plpython',
            'pltcl',
        ].each |$ext| {
            package { "postgresql-${ext}-${ver}": }
        }
    }
    
    #package { 'barman': }
    package { 'postgresql-filedump': }
    package { 'pgtop': }
    ensure_resource('package', 'repmgr')
    package { 'pg-backup-ctl': }
    

    # default instance must not run
    service { ["postgresql", "postgresql@${ver}-main"]:
        ensure => stopped,
        enable => false,
    }
    
    ensure_resource( service, 'repmgrd', {
        ensure => stopped,
        enable => false,
    })
}
