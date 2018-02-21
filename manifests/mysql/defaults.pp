#
# Copyright 2017-2018 (c) Andrey Galkin
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

    $min_memory = 128
    $min_arb_memory = 16
    $max_memory = undef
    $max_arb_memory = 128
}
