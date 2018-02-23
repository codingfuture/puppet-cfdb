#
# Copyright 2018 (c) Andrey Galkin
#

define cfdb::elasticsearch::clusterports(
    Cfnetwork::Ifacename $iface,
    String[1] $cluster,
    String[1] $user,
    String[1] $ipset,
    Cfnetwork::Port $peer_port,
) {
    assert_private()

    $cluster_port = cfdb::derived_port($peer_port, 'elasticsearch')

    ensure_resource('cfnetwork::describe_service', "cfdb_${cluster}_peer", {
        server => "tcp/${cluster_port}",
    })

    cfnetwork::client_port { "${iface}:cfdb_${cluster}_peer":
        dst  => "ipset:${ipset}",
        user => $user,
    }
    cfnetwork::service_port { "${iface}:cfdb_${cluster}_peer":
        src => "ipset:${ipset}",
    }
}
