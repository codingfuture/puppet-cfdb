#
# Copyright 2018 (c) Andrey Galkin
#

class cfdb::elasticsearch::curator {
    include cfdb::elasticsearch

    $python_deps = [ 'python3-pip', 'python3-setuptools' ]
    ensure_packages( $python_deps )

    package { 'elasticsearch-curator':
        ensure   => latest,
        provider => pip3,
        require  => Package[$python_deps],
    }
}
