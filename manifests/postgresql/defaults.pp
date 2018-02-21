#
# Copyright 2017-2018 (c) Andrey Galkin
#

class cfdb::postgresql::defaults {
    $latest = '10'

    $old = cfsystem::query([
        'resources[parameters]{ ',
            "certname = '${::trusted['certname']}' and ",
            "title='Cfdb::Postgresql' and type='Class' }"
    ].join(' '))
    $version = pick($old.dig(0, 'parameters', 'version'), $latest)

    $min_memory = 128
    $min_arb_memory = 64
    $max_memory = undef
    $max_arb_memory = 128
}
