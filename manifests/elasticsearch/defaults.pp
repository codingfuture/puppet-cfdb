#
# Copyright 2018-2019 (c) Andrey Galkin
#

class cfdb::elasticsearch::defaults {
    $latest = '6'

    $old = cfsystem::query([
        'resources[parameters]{ ',
            "certname = '${::trusted['certname']}' and ",
            "title='Cfdb::Elasticsearch' and type='Class' }"
    ].join(' '))
    $version = pick($old.dig(0, 'parameters', 'version'), $latest)

    # only half is to be used for heap
    $min_memory = 512
    $min_arb_memory = 128
    $max_memory = 64 * 1024
    $max_arb_memory = 256
}
