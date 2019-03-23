#
# Copyright 2017-2019 (c) Andrey Galkin
#

define cfdb::mongodb::healthcheck(
    String[1] $role,
    String[1] $password,
    String[1] $database,
    String[1] $cluster = $title,
) {
    include cfdb::haproxy

    $conf_file = "${cfdb::haproxy::conf_dir}/check_${cluster}.js"

    file { $conf_file:
        ensure  => present,
        owner   => $cfdb::haproxy::user,
        group   => $cfdb::haproxy::user,
        mode    => '0750',
        content => [
            "const tdb = db.getMongo().getDB('${database}');",
            "tdb.auth('${role}', '${password}');",
            "tdb.runCommand( { ping: 1 } )",
        ].join("\n"),
    }
}
