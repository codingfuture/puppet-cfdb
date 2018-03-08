#
# Copyright 2018 (c) Andrey Galkin
#

#
# Copyrigh 2018 (c) Andrey Galkin
#

class cfdb::elasticsearch (
    String[1]
        $version = $cfdb::elasticsearch::defaults::version,
    Boolean
        $default_extensions = true,
    Array[String[1]]
        $extensions = [],
    String[1]
        $apt_repo = 'https://artifacts.elastic.co/packages/6.x/apt',
) inherits cfdb::elasticsearch::defaults {
    include stdlib
    include cfdb

    $latest = $cfdb::elasticsearch::defaults::latest
    $actual_version = $version
    $is_cluster = true
    $is_unidb = true

    class { 'cfdb::elasticsearch::aptrepo':
        stage => setup
    }

    if versioncmp( $version, $latest ) < 0 {
        notify { "\$cfdb::elasticsearch::version ${version} is not the latest ${latest}":
            loglevel => warning,
        }
    }

    cfnetwork::client_port { 'any:cfhttp:elastic':
        user => root,
    }

    #---
    if $default_extensions {
        $def_plugins = [
            'analysis-icu',
            'ingest-geoip',
        ]
    } else {
        $def_plugins = []
    }

    $all_plugins = $extensions + $def_plugins

    $plugin_installer = '/usr/share/elasticsearch/bin/elasticsearch-plugin-installer'

    file { $plugin_installer:
        mode    => '0700',
        content => file( 'cfdb/elasticsearch_plugin_installer.sh' ),
    }
    -> exec { 'Installing ElasticSearch plugins':
        command => "${plugin_installer} install ${all_plugins.join(' ')}",
        unless  => "${plugin_installer} check ${all_plugins.join(' ')}",
    }
}
