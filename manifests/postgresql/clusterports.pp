#
# Copyright 2017-2019 (c) Andrey Galkin
#

define cfdb::postgresql::clusterports(
    Cfnetwork::Ifacename $iface,
    String[1] $cluster,
    String[1] $user,
    String[1] $ipset,
    Cfnetwork::Port $peer_port,
) {
    assert_private()

    cfnetwork::describe_service { "cfdb_${cluster}_peer":
        server => "tcp/${peer_port}",
    }

    cfnetwork::client_port { "${iface}:cfdb_${cluster}_peer":
        dst  => "ipset:${ipset}",
        user => $user,
    }
    cfnetwork::service_port { "${iface}:cfdb_${cluster}_peer":
        src => "ipset:${ipset}",
    }
}
