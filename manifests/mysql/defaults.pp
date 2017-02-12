#
# Copyright 2017 (c) Andrey Galkin
#

class cfdb::mysql::defaults {
    $latest = '5.7'
    $latest_cluster = '5.7'

    $old = cfsystem::query([
        'resources[parameters]{ ',
            "certname = '${::trusted['certname']}' and ",
            "title='Cfdb::Mysql' and type='Class' }"
    ].join(' '))
    $version = pick($old.dig(0, 'parameters', 'version'), $latest)
    $cluster_version = pick(
        $old.dig(0, 'parameters', 'cluster_version'),
        $latest_cluster
    )
}
