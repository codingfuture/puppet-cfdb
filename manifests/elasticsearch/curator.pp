#
# Copyright 2018 (c) Andrey Galkin
#

class cfdb::elasticsearch::curator {
    include cfdb::elasticsearch
    include cfsystem::pip

    package { 'elasticsearch-curator':
        ensure   => latest,
        provider => pip3,
        require  => Package['pip3'],
    }
}
