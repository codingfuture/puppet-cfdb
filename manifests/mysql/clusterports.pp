#
# Copyright 2017 (c) Andrey Galkin
#

define cfdb::mysql::clusterports(
    Cfnetwork::Ifacename $iface,
    String[1] $cluster,
    String[1] $user,
    String[1] $ipset,
    Cfnetwork::Port $peer_port,
) {
    assert_private()

    $galera_port = cfdb::derived_port($peer_port, 'galera')
    $sst_port = cfdb::derived_port($peer_port, 'galera_sst')
    $ist_port = cfdb::derived_port($peer_port, 'galera_ist')

    # services
    cfnetwork::describe_service { "cfdb_${cluster}_peer":
        server => "tcp/${peer_port}",
    }
    cfnetwork::describe_service { "cfdb_${cluster}_galera":
        server => [
            "tcp/${galera_port}",
            "udp/${galera_port}"
        ],
    }
    cfnetwork::describe_service { "cfdb_${cluster}_sst":
        server => "tcp/${sst_port}",
    }
    cfnetwork::describe_service { "cfdb_${cluster}_ist":
        server => "tcp/${ist_port}",
    }

    # client
    cfnetwork::client_port { "${iface}:cfdb_${cluster}_peer":
        dst  => "ipset:${ipset}",
        user => $user,
    }
    cfnetwork::client_port { "${iface}:cfdb_${cluster}_galera":
        dst  => "ipset:${ipset}",
        user => $user,
    }
    cfnetwork::client_port { "${iface}:cfdb_${cluster}_sst":
        dst  => "ipset:${ipset}",
        user => $user,
    }
    cfnetwork::client_port { "${iface}:cfdb_${cluster}_ist":
        dst  => "ipset:${ipset}",
        user => $user,
    }

    # listen
    cfnetwork::service_port { "${iface}:cfdb_${cluster}_peer":
        src => "ipset:${ipset}",
    }
    cfnetwork::service_port { "${iface}:cfdb_${cluster}_galera":
        src => "ipset:${ipset}",
    }
    cfnetwork::service_port { "${iface}:cfdb_${cluster}_sst":
        src => "ipset:${ipset}",
    }
    cfnetwork::service_port { "${iface}:cfdb_${cluster}_ist":
        src => "ipset:${ipset}",
    }
}
