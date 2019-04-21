#
# Copyright 2016-2019 (c) Andrey Galkin
#


class cfdb::postgresql::serverpkg {
    assert_private()

    include cfdb
    include cfdb::postgresql
    include cfdb::postgresql::arbitratorpkg

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
            $ext_packages = [
                "postgresql-${ver}-asn1oid",
                "postgresql-${ver}-debversion",
                "postgresql-${ver}-ip4r",
                "postgresql-${ver}-pgextwlist",
                "postgresql-${ver}-pgmp",
                "postgresql-${ver}-pgrouting",
                "postgresql-${ver}-pllua",
                "postgresql-${ver}-plproxy",
                "postgresql-${ver}-plr",
                "postgresql-${ver}-plv8",
                "postgresql-${ver}-postgis-2.2",
                "postgresql-${ver}-postgis-scripts",
                "postgresql-${ver}-powa",
                "postgresql-${ver}-prefix",
                "postgresql-${ver}-preprepare",
                "postgresql-plperl-${ver}",
                "postgresql-plpython3-${ver}",
                "postgresql-contrib-${ver}",
            ]
        }
        '9.6': {
            $ext_packages = [
                "postgresql-${ver}-asn1oid",
                "postgresql-${ver}-debversion",
                "postgresql-${ver}-ip4r",
                "postgresql-${ver}-pgextwlist",
                "postgresql-${ver}-pgmp",
                "postgresql-${ver}-pgrouting",
                "postgresql-${ver}-pllua",
                "postgresql-${ver}-plproxy",
                "postgresql-${ver}-plr",
                "postgresql-${ver}-plv8",
                "postgresql-${ver}-postgis-2.3",
                "postgresql-${ver}-postgis-scripts",
                "postgresql-${ver}-powa",
                "postgresql-${ver}-prefix",
                "postgresql-${ver}-preprepare",
                "postgresql-plperl-${ver}",
                "postgresql-plpython3-${ver}",
                "postgresql-contrib-${ver}",
            ]
        }
        '10': {
            $ext_packages = [
                "postgresql-${ver}-asn1oid",
                "postgresql-${ver}-debversion",
                "postgresql-${ver}-ip4r",
                "postgresql-${ver}-pgextwlist",
                "postgresql-${ver}-pgmp",
                "postgresql-${ver}-pllua",
                "postgresql-${ver}-plproxy",
                "postgresql-${ver}-plr",
                "postgresql-${ver}-plv8",
                "postgresql-${ver}-postgis-2.4-scripts",
                "postgresql-${ver}-powa",
                "postgresql-${ver}-prefix",
                "postgresql-${ver}-preprepare",
                "postgresql-plperl-${ver}",
                "postgresql-plpython3-${ver}",
            ]
        }
        default: {
            $ext_packages = []
        }
    }

    if $cfdb::postgresql::default_extensions {
        ensure_packages($ext_packages)
    }

    ensure_packages([
        'postgresql-filedump',
        'pgtop',
        "postgresql-${ver}-repmgr",
    ])

    # Official repo supplies only v0.8, but pg v10 required v1.0+
    # 'pg-backup-ctl'
    file { '/usr/bin/pg_backup_ctl':
        mode    => '0755',
        content => file('cfdb/pg_backup_ctl'),
    }

    # default instance must not run
    service { ['postgresql', "postgresql@${ver}-main"]:
        ensure   => stopped,
        enable   => mask,
        provider => 'systemd',
    }
}
