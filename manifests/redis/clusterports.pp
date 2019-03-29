#
# Copyright 2019 (c) Andrey Galkin
#

define cfdb::redis::clusterports(
    Cfnetwork::Ifacename $iface,
    String[1] $cluster,
    String[1] $user,
    String[1] $ipset,
    Cfnetwork::Port $peer_port,
) {
    assert_private()

    $sentinel_port = cfdb::derived_port($peer_port, 'sentinel')

    cfnetwork::describe_service { "cfdb_${cluster}_sentinel":
        server => [
            "tcp/${sentinel_port}",
        ],
    }

    cfnetwork::client_port { "${iface}:cfdb_${cluster}:peers":
        dst  => "ipset:${ipset}",
        user => $user,
    }
    cfnetwork::service_port { "${iface}:cfdb_${cluster}:peers":
        src => "ipset:${ipset}",
    }

    cfnetwork::client_port { "${iface}:cfdb_${cluster}_sentinel":
        dst  => "ipset:${ipset}",
        user => $user,
    }
    cfnetwork::service_port { "${iface}:cfdb_${cluster}_sentinel":
        src => "ipset:${ipset}",
    }

    cfnetwork::client_port { "local:cfdb_${cluster}_sentinel":
        user => $user,
    }
    cfnetwork::service_port { "local:cfdb_${cluster}_sentinel": }
}
