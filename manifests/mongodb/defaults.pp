#
# Copyright 2019 (c) Andrey Galkin
#

class cfdb::mongodb::defaults {
    $latest = '3.6'

    $old = cfsystem::query([
        'resources[parameters]{ ',
            "certname = '${::trusted['certname']}' and ",
            "title='Cfdb::Mongodb' and type='Class' }"
    ].join(' '))
    $version = pick($old.dig(0, 'parameters', 'version'), $latest)

    $min_memory = 256
    $min_arb_memory = 16
    $max_memory = undef
    $max_arb_memory = 128
}
