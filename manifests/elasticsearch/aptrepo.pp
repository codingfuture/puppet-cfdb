#
# Copyright 2018-2019 (c) Andrey Galkin
#


class cfdb::elasticsearch::aptrepo {
    assert_private()

    include cfsystem

    cfsystem::apt::key {'elasticsearch':
        id      => '46095ACC8548582C1A2699A9D27D666CD88E42B4',
    }

    apt::source { 'elasticsearch':
        location => $cfdb::elasticsearch::apt_repo,
        release  => 'stable',
        repos    => 'main',
        pin      => $cfsystem::apt_pin + 1,
        require  => Apt::Key['cfsystem_elasticsearch'],
        notify   => Class['apt::update'],
    }
}
