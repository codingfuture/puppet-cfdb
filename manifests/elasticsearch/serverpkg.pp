#
# Copyright 2018 (c) Andrey Galkin
#


class cfdb::elasticsearch::serverpkg {
    assert_private()

    include cfdb
    include cfdb::elasticsearch

    $ver = $cfdb::elasticsearch::actual_version

    apt::pin{ 'elasticsearch-ver':
        order    => 99,
        priority => $cfsystem::apt_pin + 2,
        version  => $ver,
        packages => [
            'apm-server',
            'auditbeat',
            'elasticsearch',
            'filebeat',
            'heartbeat-elastic',
            'logstash',
            'kibana',
            'metricbeat',
            'packetbeat',
        ],
    }

    ensure_resource( 'package', 'openjdk-8-jre-headless' )
    package { 'elasticsearch': ensure => $ver }

    # default instance must not run
    service { 'elasticsearch':
        ensure   => stopped,
        enable   => false,
        provider => 'systemd',
    }

    file { '/etc/default/elasticsearch':
        ensure  => present,
        mode    => '0755',
        content => '',
    }
}
