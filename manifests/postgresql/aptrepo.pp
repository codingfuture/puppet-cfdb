#
# Copyright 2016-2019 (c) Andrey Galkin
#


class cfdb::postgresql::aptrepo {
    assert_private()

    include cfsystem

    $lsbdistcodename = $::facts['lsbdistcodename']
    $postgresql_release = $::facts['operatingsystem'] ? {
        'Debian' => (versioncmp($::facts['operatingsystemrelease'], '10') >= 0) ? {
            true    => 'sid',
            default => $lsbdistcodename
        },
        'Ubuntu' => (versioncmp($::facts['operatingsystemrelease'], '18.04') >= 0) ? {
            true    => 'bionic',
            default => $lsbdistcodename
        },
        default  => $lsbdistcodename
    }

    cfsystem::apt::key {'postgresql':
        id      => 'B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8',
    }

    apt::source { 'postgresql':
        location => $cfdb::postgresql::apt_repo,
        release  => "${postgresql_release}-pgdg",
        repos    => 'main',
        pin      => $cfsystem::apt_pin + 1,
        require  => Apt::Key['cfsystem_postgresql'],
        notify   => Class['apt::update'],
    }
}
