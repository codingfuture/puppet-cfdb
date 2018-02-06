#
# Copyright 2016-2018 (c) Andrey Galkin
#


class cfdb::postgresql::serverpkg {
    assert_private()

    include cfdb
    include cfdb::postgresql

    $ver = $cfdb::postgresql::version

    apt::pin{ 'postgresql-ver':
        order    => 99,
        priority => $cfsystem::apt_pin + 2,
        version  => "${ver}.*",
        packages => [
            'postgresql',
            'postgresql-all',
            'postgresql-client',
            'postgresql-contrib',
            'postgresql-server',
        ],
    }

    package { "postgresql-${ver}": }

    $cfdb::postgresql::extensions.each |$ext| {
        ensure_resource('package', "postgresql-${ver}-${ext}", {})
    }
    $cfdb::postgresql::extensions2.each |$ext| {
        ensure_resource('package', "postgresql-${ext}-${ver}", {})
    }

    case $ver {
        '9.5': {
            $postgis_ver = '2.2'
        }
        '9.6': {
            $postgis_ver = '2.3'
        }
        '10': {
            $postgis_ver = '2.4'
        }
        default: {
            $postgis_ver = '2.4'
        }
    }

    if $cfdb::postgresql::default_extensions {
        #'repack',
        #'partman',
        # 'pgespresso' - deprecated with 9.6,
        [
            'asn1oid',
            'debversion',
            'ip4r',
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
        ].each |$ext| {
            ensure_resource('package', "postgresql-${ver}-${ext}", {})
        }

        # 'pltcl',
        # 'contrib' - virtual since 10
        [
            'plperl',
            'plpython3',
        ].each |$ext| {
            ensure_resource('package', "postgresql-${ext}-${ver}", {})
        }

  if versioncmp( $ver, '10' ) < 0 {
            ensure_resource('package', "postgresql-contrib-${ver}", {})
  }
    }

    ensure_packages([
        'postgresql-filedump',
        'pgtop',
        'repmgr',
        "postgresql-${ver}-repmgr",
        'pg-backup-ctl'
    ])


    # default instance must not run
    service { ['postgresql', "postgresql@${ver}-main"]:
        ensure   => stopped,
        enable   => false,
        provider => 'systemd',
    }

    ensure_resource( service, 'repmgrd', {
        ensure   => stopped,
        enable   => false,
        provider => 'systemd',
    })
}
