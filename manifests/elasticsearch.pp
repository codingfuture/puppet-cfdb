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
        $extensions = [
            'elasticsearch-sql',
        ],
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
}
