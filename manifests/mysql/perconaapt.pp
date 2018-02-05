#
# Copyright 2016-2018 (c) Andrey Galkin
#


class cfdb::mysql::perconaapt {
    assert_private()

    include cfsystem

    $lsbdistcodename = $::facts['lsbdistcodename']
    $percona_release = $::facts['operatingsystem'] ? {
        'Debian' => (versioncmp($::facts['operatingsystemrelease'], '10') >= 0) ? {
            true    => 'stretch',
            default => $lsbdistcodename
        },
        'Ubuntu' => (versioncmp($::facts['operatingsystemrelease'], '17.04') >= 0) ? {
            true    => 'zesty',
            default => $lsbdistcodename
        },
        default  => $lsbdistcodename
    }

    $gpg_keys = [
        'deb-percona-keyring-old.gpg',
        'deb-percona-keyring.gpg',
    ]

    $key_deps = $gpg_keys.map |$v| {
        $f = "/etc/apt/trusted.gpg.d/${v}"
        file { $f:
            content => file("cfdb/${v}"),
            notify  => Class['apt::update'],
        }
        File[$f]
    }

    apt::source { 'percona':
        location => $cfdb::mysql::percona_apt_repo,
        release  => $percona_release,
        repos    => 'main',
        pin      => $cfsystem::apt_pin + 1,
        require  => $key_deps,
        notify   => Class['apt::update'],
    }

    package { 'percona-release': ensure => absent }
}
