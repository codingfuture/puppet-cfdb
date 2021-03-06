#
# Copyright 2018-2019 (c) Andrey Galkin
#

define cfdb::elasticsearch::healthcheck(
    String[1] $role,
    String[1] $password,
    String[1] $database,
    String[1] $cluster = $title,
) {
    include cfdb::haproxy

    $conf_file = "${cfdb::haproxy::conf_dir}/check_${cluster}.cnf"

    file { $conf_file:
        ensure  => present,
        owner   => $cfdb::haproxy::user,
        group   => $cfdb::haproxy::user,
        mode    => '0750',
        content => [
        ].join("\n"),
    }
}
