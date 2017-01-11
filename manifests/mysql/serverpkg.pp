#
# Copyright 2016-2017 (c) Andrey Galkin
#


class cfdb::mysql::serverpkg {
    assert_private()

    include cfdb
    include cfdb::mysql

    $ver = $cfdb::mysql::actual_version

    if $cfdb::mysql::is_cluster {
        $ver_nodot = regsubst($ver, '\.', '', 'G')
        package { "percona-xtradb-cluster-${ver_nodot}": }
    } else {
        $xtrabackup_ver = '24'
        package { "percona-server-server-${ver}": }
        package { "percona-xtrabackup-${xtrabackup_ver}": }
    }

    package { 'qpress': }
    package { 'percona-toolkit': }

    # default instance must not run
    service { 'mysql':
        ensure   => stopped,
        enable   => false,
        provider => 'systemd',
    }

    # Workaround for stupid MySQL pre-inst script
    file { '/usr/sbin/cfmysqld':
        ensure => link,
        target => '/usr/sbin/mysqld',
    }
}
