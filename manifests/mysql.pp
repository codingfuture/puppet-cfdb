#
# Copyright 2016-2018 (c) Andrey Galkin
#

class cfdb::mysql (
    Boolean
        $is_cluster = false,
    String[1]
        $percona_apt_repo = 'http://repo.percona.com/apt',
    String[1]
        $version = $cfdb::mysql::defaults::version,
    String[1]
        $cluster_version = $cfdb::mysql::defaults::cluster_version,
) inherits cfdb::mysql::defaults {
    #assert_private()

    include stdlib
    include cfdb

    if $is_cluster {
        $actual_version = $cluster_version
    } else {
        $actual_version = $version
    }

    class { 'cfdb::mysql::perconaapt':
        stage => setup
    }

    $latest = $cfdb::mysql::defaults::latest
    $latest_cluster = $cfdb::mysql::defaults::latest_cluster
    $is_unidb = false

    if $version != $latest {
        cf_notify { "\$cfdb::mysql::version ${version} is not the latest ${latest}":
            loglevel => warning,
        }
    }

    if versioncmp( $cluster_version, $latest_cluster ) < 0 {
        cf_notify { "\$cfdb::mysql::cluster_version ${cluster_version} is not the latest ${latest_cluster}":
            loglevel => warning,
        }
    }
}
