#
# Copyright 2019 (c) Andrey Galkin
#

class cfdb::redis::defaults {
    $min_memory = 16
    $min_arb_memory = $min_memory
    $max_memory = undef
    $max_arb_memory = $min_memory
}
