#
# Copyright 2018-2019 (c) Andrey Galkin
#


class cfdb::elasticsearch::serverpkg {
    assert_private()

    include cfdb
    include cfdb::elasticsearch

    $ver = $cfdb::elasticsearch::actual_version

    apt::pin{ 'elasticsearch-ver':
        order    => 99,
        priority => $cfsystem::apt_pin + 2,
        version  => "${ver}.*",
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

    Package['openjdk-8-jre-headless']
    -> file { '/etc/default/elasticsearch':
        ensure  => present,
        mode    => '0755',
        content => [
            'ES_PATH_CONF=/etc/elasticsearch',
            ''
        ].join("\n"),
    }
    -> package { 'elasticsearch': }
    # default instance must not run
    -> service { 'elasticsearch':
        ensure   => stopped,
        enable   => mask,
        provider => 'systemd',
    }

    #---
    if $cfdb::elasticsearch::default_extensions {
        $def_plugins = [
            'analysis-icu',
            'ingest-geoip',
        ]
    } else {
        $def_plugins = []
    }

    $all_plugins = $cfdb::elasticsearch::extensions + $def_plugins

    $plugin_installer = '/usr/share/elasticsearch/bin/elasticsearch-plugin-installer'

    file { $plugin_installer:
        mode    => '0700',
        content => file( 'cfdb/elasticsearch_plugin_installer.sh' ),
    }
    -> exec { 'Installing ElasticSearch plugins':
        command => "${plugin_installer} install ${all_plugins.join(' ')}",
        unless  => "${plugin_installer} check ${all_plugins.join(' ')}",
        require => Package['elasticsearch'],
    }
    -> file { '/etc/elasticsearch/ingest-geoip':
        ensure => directory,
        mode   => '0750',
    }
}
