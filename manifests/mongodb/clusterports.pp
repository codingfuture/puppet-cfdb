#
# Copyright 2017-2019 (c) Andrey Galkin
#

define cfdb::mongodb::clusterports(
    Cfnetwork::Ifacename $iface,
    String[1] $cluster,
    String[1] $user,
    String[1] $ipset,
    Cfnetwork::Port $peer_port,
) {
    assert_private()

    # client
    cfnetwork::client_port { "${iface}:cfdb_${cluster}:peers":
        dst  => "ipset:${ipset}",
        user => $user,
    }

    # listen
    cfnetwork::service_port { "${iface}:cfdb_${cluster}:peers":
        src => "ipset:${ipset}",
    }
}
