# cfdb

## Description

* Setup & auto tune service instances based on available resources
    * MySQL
    * PostgreSQL
    * a general framework to easily add new types is available
* Support auto-configurable clustering
    * Galera Cluster for MySQL
    * repmgr for PostgreSQL
* High Availability and fail-over out-of-the-box
    * Specialized HAProxy on each client system
* Automatic creation of databases
* Automatic upgrade of databases with DB software upgrade
* Complete management of user accounts (roles)
    * automatic random password management
    * full & read-only database out of the box
    * custom grants support
    * ensures max connections meet
* Easy access configuration
    * automatic firewall setup on both client & server side
    * automatic protection for incoming hosts
    * automatic protection for max connections
* Automatic backup and automated restore

### Terminology & Concept

* `cluster` - unique associative name for a collection of distributed database instances.
    In standalone cases, there is only one instance per cluster.
* `instance` - database service process and related configuration. Each instance runs in
    own cgroup for fair weighted usage of RAM, CPU and I/O resources.
    - `primary instance` - instance where dynamic setup of roles and databases occurs. It also
        gets all Read-Write users by default.
    - `secondary instance` - a slave instance suitable for temporary automatic fail-over and
        Read-Only users. It is not allowed to define databases & roles in configuration, unless
        the instance is switched to primary node in static configuration.
    - `arbitrator` - an instance participating in quorum, but with no data. Mitigates
        split-brain cases.
* `database` - a database instance per cluster. All privileged on the database role with the same
    name is automatically created. There is no need to define such role explicitly.
* `role` - a database user. Each role name is automatically prefixed with related database name
    to prevent name collisions.
* `access` - a definition of client system and user to access particular role on specific database of specific cluster.
    All connections parameters are saved in ".env" file in user's home folder. It's possible
    to specify multiple access definitions per single system user using different .env variable prefixes.
    In case of multi-node cluster, a local HAProxy reverse-proxy instance is implicitly created with required
    high-Availability configuration.


## Technical Support

* [Example configuration](https://github.com/codingfuture/puppet-test)
* Commercial support: [support@codingfuture.net](mailto:support@codingfuture.net)

## Setup

Please use [librarian-puppet](https://rubygems.org/gems/librarian-puppet/) or
[cfpuppetserver module](https://forge.puppetlabs.com/codingfuture/cfpuppetserver) to deal with dependencies.

There is a known r10k issue [RK-3](https://tickets.puppetlabs.com/browse/RK-3) which prevents
automatic dependencies of dependencies installation.

### IMPORTANT NOTES!!!

Please understand that PuppetDB is heavily used for auto-configuration. The drawback is that 
new facts are updated only on second run after the run which makes any changes. Typical case 
is to do the following:

1. Provision instance with databases & roles
2. Provision the same instance again (collect facts)
3. Provision access locations
4. Provision access locations again (collect facts)
5. Provision instance (update configuration based on the access facts)
6. Restart instances, if asked during provisioning
6. Provision all nodes in cycle until there are no new changes and no restart is required

For cluster configuration:
1. Provision primary node
2. Provision primary node again (collect facts)
3. Provision secondary nodes
4. Provision secondary nodes again (collect facts)
5. Provision primary node (configure firewall & misc. based on facts)
6. Provision secondary nodes again (clone/setup)
7. Restart instances, if asked during provisioning
8. Provision all nodes in cycle until there are no new changes and no restart is required

## Examples

Please check [codingufuture/puppet-test](https://github.com/codingfuture/puppet-test) for
example of a complete infrastructure configuration and Vagrant provisioning.

## Implicitly created resources

```yaml
# for every instance
#------------------
cfnetwork::describe_service:
    cfdb_${cluster}:
        server: "tcp/${port}"

# local cluster system user access to own instance
cfnetwork::service_port:
    "local:cfdb_${cluster}": {}
cfnetwork::client_port:
    "local:cfdb_${cluster}":
        user: $user

# client access to local cluster instance
cfnetwork::service_port:
    "${iface}:cfdb_${cluster}":
        src: $client_hosts
        
# for each Galera cluster (inter-node comms)
# > access to local instance ports
cfnetwork::describe_service:
    "cfdb_${cluster}_peer":
        server: "tcp/${port}"
    "cfdb_${cluster}_galera":
        server:
            - "tcp/${galera_port}"
            - "udp/${galera_port}"
    "cfdb_${cluster}_sst":
        server: "tcp/${sst_port}"
    "cfdb_${cluster}_ist":
        server: "tcp/${ist_port}"
cfnetwork::service_port:
    "${iface}:cfdb_${cluster}_peer":
        src: $peer_addr_list
    "${iface}:cfdb_${cluster}_galera":
        src: $peer_addr_list
    "${iface}:cfdb_${cluster}_sst":
        src: $peer_addr_list
    "${iface}:cfdb_${cluster}_ist":
        src: $peer_addr_list
# > access to remote cluster instances
cfnetwork::describe_service:
    "cfdb_${cluster}_peer_${host_under}":
        server: "tcp/${peer_port}"
    "cfdb_${cluster}_galera_${host_under}":
        server:
            - "tcp/${galera_port}"
            - "udp/${galera_port}"
    "cfdb_${cluster}_sst_${host_under}":
        server: "tcp/${sst_port}"
    "cfdb_${cluster}_ist_${host_under}":
        server: "tcp/${ist_port}"
cfnetwork::client_port:
    "${iface}:cfdb_${cluster}_peer_${host_underscore}":
        dst: $peer_addr
        user: $user
    "${iface}:cfdb_${cluster}_galera_${host_underscore}":
        dst: $peer_addr
        user: $user
    "${iface}:cfdb_${cluster}_sst_${host_underscore}":
        dst: $peer_addr
        user: $user
    "${iface}:cfdb_${cluster}_ist_${host_underscore}":
        dst: $peer_addr
        user: $user

# for each repmgr PostgreSQL cluster (inter-node comms)
# > access to local instance ports
cfnetwork::describe_service:
    "cfdb_${cluster}_peer":
        server: "tcp/${port}"
cfnetwork::service_port:
    "${iface}:cfdb_${cluster}_peer":
        src: $peer_addr_list
        
# > access to remote cluster instances
cfnetwork::describe_service:
    "cfdb_${cluster}_peer_${host_under}":
        server: "tcp/${peer_port}"
cfnetwork::client_port:
    "${iface}:cfdb_${cluster}_peer_${host_under}":
        dst: $peer_addr
        user: $user

# for each cluster node requiring SSH access (e.g. repmgr)
cfnetwork::client_port:
    "${iface}:cfssh:cfdb_${cluster}_${host_underscore}":
        dst: $peer_addr
        user: $user
cfnetwork::service_port:
    "${iface}:cfssh:cfdb_${cluster}_${host_underscore}":
        src: $peer_addr


# for every cfdb::access when HAProxy is NOT used
#------------------
cfnetwork::describe_service:
    cfdb_${cluster}:
        server: "tcp/${port}"
cfnetwork::client_port:
    "any:cfdb_${cluster}:${local_user}":
        dst: [cluster_hosts]
        user: $local_user

# for every cfdb::access when HAProxy IS used
#------------------
cfnetwork::describe_service:
    "cfdbha_${cluster}_${port}":
        server: "tcp/${port}"
cfnetwork::client_port:
    "any:${fw_service}:${host_under}":
        dst: $addr,
        user: $cfdb::haproxy::user
```

## class `cfdb` parameters
This is a full featured class to use with Hiera

* `$instances = {}` - configurations for cfdb::instance resources (Hiera-friendly)
* `$access = {}` - configurations for cfdb::access resources (Hiera-friendly)
* `$iface = 'any'` - database network facing interface
* `$root_dir = '/db'` - root to create instance home folders
* `$max_connections_default = 10` - default value for cfdb::access::max_connections
* `$backup = true` - default value for cfdb::instance::backup

## class `cfdb::backup` parameters
This class is included automatically on demand.

* `$cron = { hour => 3, minute => 10 }` - default `cron` config for periodic auto-backup
* `$root_dir = '/mnt/backup'` - root folder for instance backup sub-folders


## class `cfdb::haproxy` parameters
This class is included automatically on demand.

* `$memory_weight = 1` - weighted amount of memory to reserve for HAProxy (note: optimal
    amount is automatically reserved based on max number of connections)
* `$memory_max = undef` - possible max memory limit
* `$cpu_weight = 100` - CPU weight for cgroup isolation
* `$io_weight = 100` - I/O weight for cgroup isolation
* `$settings_tune = {}` - do not use, unless you know what you are doing. Mostly left for
    exceptional in-field case purposes.

## class `cfdb::mysql` parameters
This class is included automatically on demand.

* `$is_cluster = false` - if true, Percona XtraDB Cluster is installed instead of Percona Server
* `$percona_apt_repo = 'http://repo.percona.com/apt'` - Percona APT repository location
* `$version = '5.7'` - version of Percona Server to use
* `$cluster_version = '5.6'` - version of PXC to use

## class `cfdb::postgresql` parameters
This class is included automatically on demand.

* `$version = '9.5'` - version of postgresql to use
* `$default_extensions = true` - install default extension list, if true.
    * Default list: 'asn1oid', 'debversion', 'ip4r', 'partman', 'pgespresso', 'pgextwlist', 'pgmp',
            'pgrouting', 'pllua', 'plproxy', 'plr', 'plv8', "postgis-${postgis_ver}", 'postgis-scripts',
            'powa', 'prefix', 'preprepare', 'repack', 'repmgr', 'contrib',
            'plperl', 'plpython', 'pltcl'
* `$extensions = []` - custom list of extensions to install
* `$apt_repo = 'http://apt.postgresql.org/pub/repos/apt/'` - PostgreSQL APT repository location

## type `cfdb::access` parameters
This type defines client with specific properties for auto-configuration of instances.

* `$cluster` - unique cluster name
* `$role` - unique role name within cluster (note roles defined in databases must be prefixed with database name)
* `$local_user` - local user to make `.env` configuration for. The `user` resource must be defined with `$home` parameter.
* `$use_proxy = 'auto'` - do not change the default (for future use)
* `$max_connections = $cfdb::max_connections_default` - define max number of client connections for particular case.
* `$config_prefix = 'DB_'` - variable prefix for `.env` file. The following variables are defined:
    'HOST', 'PORT', 'SOCKET', 'USER', 'PASS', 'TYPE'.
* `$env_file = '.env'` - name of dot-env file relative to $home of the user
* `$iface = $cfdb::iface` - DB network facing interface

## type `cfdb::database` parameters
This type must be used only on primary instance of cluster.

* `$cluster` - unique cluster name
* `$database` - database name
* `$roles = undef` - configuration for `cfdb::role` resources (Hiera-friendly)


## type `cfdb::instance` parameters
Defines and auto-configures instances.

* `$type` - type of cluster, e.g. mysql, postgresql
* `$is_cluster = false` - if true, configured instance with cluster in mind
* `$is_secondary = false` - if true, secondary node is assumed
* `$is_bootstrap = false` - if true, forces cluster bootstrap (should be used only TEMPORARY for recovery purposes)
* `$is_arbitrator = false` - if true, assumes a witness node for quorum with no data
*
* `$memory_weight = 100` - relative memory weight for automatic configuration based on available RAM
* `$memory_max = undef` - max memory the instance can use in auto-configuration
* `$cpu_weight = 100` - relative CPU weight for cgroup isolation
* `$io_weight = 100` - relative I/O weight for cgroup isolation
* `$target_size = 'auto'` - expected database size in bytes (auto - detects based on partition size)
*
* `$settings_tune = {}` - very specific fine tune. See below
* `$databases = undef` - configuration for cfdb::database resources
*
* `$iface = $cfdb::iface` - DB network facing interface
* `$port = undef` - force specific network port (mandatory, if $is_cluster)
*
* `$backup = $cfdb::backup` - if true, automatic scheduled backup gets enabled
* `$backup_tune = {}` - for future use, overrides $type specific backup script parameters
*
* `$ssh_key_type = 'ed25519'` - SSH key type for in-cluster communication
* `$ssh_key_bits = 2048` - SSH key bits for RSA


# `$settings_tune` magic

## MySQL
TBD.

## PostgreSQL
TBD.

## HAProxy
TBD.
