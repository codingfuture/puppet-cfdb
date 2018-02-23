#
# Copyright 2016-2018 (c) Andrey Galkin
#


class cfdb::mysql::serverpkg {
    assert_private()

    include cfdb
    include cfdb::mysql

    $ver = $cfdb::mysql::actual_version

    apt::pin{ 'percona-ver':
        order    => 99,
        priority => $cfsystem::apt_pin + 2,
        version  => "${ver}.*",
        packages => [
            'percona-server-server',
            'percona-server-client',
        ],
    }

    if $cfdb::mysql::is_cluster {
        $ver_nodot = regsubst($ver, '\.', '', 'G')
        package { "percona-xtradb-cluster-${ver_nodot}": }
        package { "percona-xtradb-cluster-server-${ver}": }
        package { "percona-xtradb-cluster-common-${ver}": }
    } else {
        $xtrabackup_ver = '24'
        package { "percona-server-server-${ver}": }
        package { "percona-server-common-${ver}": }
        package { "percona-xtrabackup-${xtrabackup_ver}": }
    }

    package { 'qpress': }
    package { 'percona-toolkit': }

    # default instance must not run
    service { 'mysql':
        ensure   => stopped,
        enable   => mask,
        provider => 'systemd',
    }

    # Workaround for stupid MySQL pre-inst script
    file { '/usr/sbin/cfmysqld':
        ensure => link,
        target => '/usr/sbin/mysqld',
    }
}
