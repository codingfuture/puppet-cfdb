#
# Copyright 2017 (c) Andrey Galkin
#

class cfdb::postgresql::defaults {
    $latest = '10'

    $old = cfsystem::query([
        'resources[parameters]{ ',
            "certname = '${::trusted['certname']}' and ",
            "title='Cfdb::Postgresql' and type='Class' }"
    ].join(' '))
    $version = pick($old.dig(0, 'parameters', 'version'), $latest)
}
