#
# Copyright 2017 (c) Andrey Galkin
#

define cfdb::postgresql::clusterports(
    String[1] $iface,
    String[1] $cluster,
    String[1] $user,
    String[1] $ipset,
    Integer[1,65535] $peer_port,
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

    # a workaround for ignorant PostgreSQL devs
    #---
    cfnetwork::service_port { "local:alludp:${cluster}-stats": }
    cfnetwork::client_port { "local:alludp:${cluster}-stats":
        user => $user,
    }
    #---
}