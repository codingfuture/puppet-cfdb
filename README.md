# cfdb

## Description

* Setup & auto tune service instances based on available resources:
    * Elasticsearch
	* MongoDB
    * MySQL
    * PostgreSQL
    * Redis
    * a general framework to easily add new types is available
* Support auto-configurable clustering:
    * Native for Elasticsearch
	* Native for MongoDB
    * Galera Cluster for MySQL
    * repmgr for PostgreSQL
    * Sentinel for Redis Master-Slave
* High Availability and fail-over out-of-the-box
    * Specialized HAProxy on each client system
* Support for secure TLS tunnel with mutual authentication for
    database connections
* Automatic creation of databases
* Automatic upgrade of databases after DB software upgrade
* Complete management of user accounts (roles)
    * automatic random generated password management
    * full & read-only database roles
    * custom grants support
    * ensures max connections meet
    * PostgreSQL extension support
* Easy access configuration
    * automatic firewall setup on both client & server side
    * automatic protection for roles x incoming hosts
    * automatic protection for roles x max connections
* Automatic incremental backup and automated restore
* Strict cgroup-based resource isolation on top of `systemd` integration
* Automatic DB connection availability checks
* Automatic cluster state checks
* Support easy migration from default data dirs (see `init_db_from`).
* Scheduled actions:
    * For example, log cleanup in ELK stack

### Terminology & Concept

* `cluster` - infrastructure-wide unique associative name for a collection of distributed database instances.
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
* Free & Commercial support: [support@codingfuture.net](mailto:support@codingfuture.net)

## Setup

Up to date installation instructions are available in Puppet Forge: https://forge.puppet.com/codingfuture/cfdb

Please use [librarian-puppet](https://rubygems.org/gems/librarian-puppet/) or
[cfpuppetserver module](https://codingfuture.net/docs/cfpuppetserver) to deal with dependencies.

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

As available system memory is automatically distributed between all registered services:
1. Please make sure to restart services after distribution gets changes (or you may run in trouble).
2. Please avoid using the same system for `codingfuture` derived services and custom. Or see #3.
3. Please make sure to reserve RAM using `cfsystem_memory_weight` for any custom co-located services. Example:
```
cfsystem_memory_weight { 'my_own_services':
        ensure => present,
        weight => 100,
        min_mb => 100,
        max_mb => 1024
    }
```

## Examples

Please check [codingufuture/puppet-test](https://github.com/codingfuture/puppet-test) for
example of a complete infrastructure configuration and Vagrant provisioning.

Example for host running standalone instances, PXC arbitrator & PostgreSQL slaves + related accesses.
```yaml
cfdb::iface: main
cfdb::instances:
    mysrv1:
        type: mysql
        databases:
            - db1_1
            - db1_2
        iface: vagrant
        port: 3306
    mysrv2:
        type: mysql
        databases:
            db2:
                roles:
                    readonly:
                        readonly: true
                    sandbox:
                        custom_grant: 'GRANT SELECT ON $database.* TO $user; GRANT SELECT ON mysql.* TO $user;'
    myclust1:
        type: mysql
        is_arbitrator: true
        port: 4306
    myclust2:
        type: mysql
        is_arbitrator: true
        port: 4307
        settings_tune:
            cfdb:
                secure_cluster: true
    pgsrv1:
        type: postgresql
        iface: vagrant
        databases:
            pdb1: {}
            pdb2: {}

    pgclust1:
        type: postgresql
        is_arbitrator: true
        is_secondary: true
        port: 5300
        settings_tune:
            cfdb:
                node_id: 3
    pgclust2:
        type: postgresql
        is_arbitrator: true
        is_secondary: true
        port: 5301
        settings_tune:
            cfdb:
                secure_cluster: true
                node_id: 3

    esearch:
        type: elasticsearch
        port: 9200
                        
cfdb::access:
    vagrant_mysrv2_db2:
        cluster: mysrv2
        role: db2
        local_user: vagrant
        max_connections: 100
    vagrant_mysrv2_db2ro:
        cluster: mysrv2
        role: db2readonly
        local_user: vagrant
        config_prefix: 'DBRO_'
        max_connections: 200
    vagrant_mysrv2_db2sandbox:
        cluster: mysrv2
        role: db2sandbox
        local_user: vagrant
        config_prefix: 'DBSB_'
    vagrant_myclust1_db1:
        cluster: myclust1
        role: db1
        local_user: vagrant
        config_prefix: 'DBC1_'
    vagrant_myclust1_db2:
        cluster: myclust1
        role: db2
        local_user: vagrant
        config_prefix: 'DBC2_'
    vagrant_pgsrv1_pdb1:
        cluster: pgsrv1
        role: pdb1
        local_user: vagrant
        config_prefix: 'PDB1_'
    vagramt_esearch:
        cluster: esearch
        local_user: vagrant
        config_prefix: 'ESRCH_'
```

For another related host running primary nodes of clusters:
```yaml
cfdb::iface: main
cfdb::mysql::is_cluster: true
cfdb::instances:
    myclust1:
        type: mysql
        is_cluster: true
        databases:
            db1:
                roles:
                    ro:
                        readonly: true
            db2: {}
        port: 3306
    myclust2:
        type: mysql
        is_cluster: true
        databases:
            - db1
            - db2
        port: 3307
        settings_tune:
            cfdb:
                secure_cluster: true
    pgclust1:
        type: postgresql
        is_cluster: true
        databases:
            pdb1:
                roles:
                    ro:
                        readonly: true
            pdb2: {}
        port: 5300
    pgclust2:
        type: postgresql
        is_cluster: true
        databases:
            - pdb3
            - pdb4
        port: 5301
        settings_tune:
            cfdb:
                secure_cluster: true

```

For third related host running secondary nodes of clusters:
```yaml
cfdb::iface: main
cfdb::mysql::is_cluster: true
cfdb::instances:
    myclust1:
        type: mysql
        is_secondary: true
        port: 3306
    myclust2:
        type: mysql
        is_secondary: true
        port: 3307
        settings_tune:
            cfdb:
                secure_cluster: true
    pgclust1:
        type: postgresql
        is_secondary: true
        port: 5300
    pgclust2:
        type: postgresql
        is_secondary: true
        port: 5301
        settings_tune:
            cfdb:
                secure_cluster: true
    esearch:
        type: elasticsearch
        is_secondary: true
        port: 9200
```

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
        
# for each repmgr Elasticsearch cluster (inter-node comms)
# > access to local instance ports
cfnetwork::describe_service:
    "cfdb_${cluster}_peer":
        server: "tcp/${peer_port}"
cfnetwork::service_port:
    "${iface}:cfdb_${cluster}_peer":
        src: $peer_addr_list
cfnetwork::service_ports:
    "${iface}:cfdb_${cluster}_peer":
        src: 'ipset:cfdb_${cluster}'
cfnetwork::client_ports:
    "${iface}:cfdb_${cluster}_peer":
        dst: 'ipset:cfdb_${cluster}'
        user: $user

# for each Galera cluster (inter-node comms)
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
cfnetwork::ipset:
    cfdb_${cluster}:
        type: ip
        addr: $peer_addr_list
cfnetwork::service_ports:
    "${iface}:cfdb_${cluster}_peer":
        src: 'ipset:cfdb_${cluster}'
    "${iface}:cfdb_${cluster}_galera":
        src: 'ipset:cfdb_${cluster}'
    "${iface}:cfdb_${cluster}_sst":
        src: 'ipset:cfdb_${cluster}'
    "${iface}:cfdb_${cluster}_ist":
        src: 'ipset:cfdb_${cluster}'
cfnetwork::client_ports:
    "${iface}:cfdb_${cluster}_peer":
        dst: 'ipset:cfdb_${cluster}'
        user: $user
    "${iface}:cfdb_${cluster}_galera":
        dst: 'ipset:cfdb_${cluster}'
        user: $user
    "${iface}:cfdb_${cluster}_sst":
        dst: 'ipset:cfdb_${cluster}'
        user: $user
    "${iface}:cfdb_${cluster}_ist":
        dst: 'ipset:cfdb_${cluster}'
        user: $user

# for each repmgr PostgreSQL cluster (inter-node comms)
# > access to local instance ports
cfnetwork::describe_service:
    "cfdb_${cluster}_peer":
        server: "tcp/${port}"
cfnetwork::service_port:
    "${iface}:cfdb_${cluster}_peer":
        src: $peer_addr_list
cfnetwork::service_ports:
    "${iface}:cfdb_${cluster}_peer":
        src: 'ipset:cfdb_${cluster}'
cfnetwork::client_ports:
    "${iface}:cfdb_${cluster}_peer":
        dst: 'ipset:cfdb_${cluster}'
        user: $user



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
    "any:${fw_service}:${host_underscore}":
        dst: $addr,
        user: $cfdb::haproxy::user
```

## class `cfdb` parameters
This is a full featured class to use with Hiera

* `$instances = {}` - configurations for `cfdb::instance` resources (Hiera-friendly)
* `$access = {}` - configurations for `cfdb::access` resources (Hiera-friendly)
* `$iface = 'any'` - database network facing interface
* `$cluster_face = 'main'` - cluster comms network facing interface
* `$root_dir = '/db'` - root to create instance home folders
* `$max_connections_default = 10` - default value for `$cfdb::access::max_connections`
* `$backup = true` - default value for `$cfdb::instance::backup`

## class `cfdb::backup` parameters
This class is included automatically on demand.

* `$cron = { hour => 3, minute => 10 }` - default `cron` config for periodic auto-backup
* `$root_dir = '/mnt/backup'` - root folder for instance backup sub-folders


## class `cfdb::haproxy` parameters
This class is included automatically on demand.

* `$memory_weight = 1` - weighted amount of memory to reserve for HAProxy.
    * *Note: optimal minimal amount is automatically reserved based on max number of connections*
* `$memory_max = undef` - possible max memory limit
* `$cpu_weight = 100` - CPU weight for cgroup isolation
* `$io_weight = 100` - I/O weight for cgroup isolation
* `$settings_tune = {}` - do not use, unless you know what you are doing. Mostly left for
    exceptional in-field case purposes.

## class `cfdb::elasticsearch` parameters
This class is included automatically on demand.

* `$version = '6'` - major or major.minor version of Elasticsearch to use
* `$apt_repo = 'https://artifacts.elastic.co/packages/6.x/apt'` - Official Elastic APT repository location
* `$default_extensions = false` - install default extension list, if true.
    - Default: 'analysis-icu' and 'ingest-geoip'
* `$extensions = []` - list of custom extensions to insall.
    - Note: elasticsearch is quite painful for exact version match.

## class `cfdb::mongodb` parameters
This class is included automatically on demand.

* `$version = '5.6'` - version of Percona Server MongoDB to use

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
    * Default list: *'asn1oid', 'debversion', 'ip4r', 'pgextwlist', 'pgmp',
            'pgrouting', 'pllua', 'plproxy', 'plr', 'plv8', "postgis-${postgis_ver}", 'postgis-scripts',
            'powa', 'prefix', 'preprepare', 'repmgr', 'contrib',
            'plpython', 'pltcl'*.
    * Note: 'plperl', 'repack' and 'partman' are disabled as they causes troubles with packaging.
* `$extensions = []` - custom list of extensions to install
* `$apt_repo = 'http://apt.postgresql.org/pub/repos/apt/'` - PostgreSQL APT repository location

## type `cfdb::access` parameters
This type defines client with specific properties for auto-configuration of instances.

* `$cluster` - unique cluster name
* `$local_user` - local user to make `.env` configuration for. The `user` resource must be defined with `$home` parameter.
* `$role = $cluster` - unique role name within cluster (note roles defined in databases must be prefixed with database name)
* `$use_proxy = 'auto'` - do not change the default (for future use)
* `$max_connections = $cfdb::max_connections_default` - define max number of client connections for particular case.
* `$config_prefix = 'DB_'` - variable prefix for `.env` file. The following variables are defined:
    * *'HOST', 'PORT', 'SOCKET', 'USER', 'PASS', 'DB', 'TYPE', 'MAXCONN'*.
    * *'CONNINFO'* - only for PostgreSQL
* `$env_file = '.env'` - name of dot-env file relative to $home of the user
* `$iface = $cfdb::iface` - DB network facing interface
* `$custom_config = undef` - name of custom resource to instantiate with the following parameters:
    * `cluster` - related cluster name
    * `role` - related role name
    * `local_user` - related local user name
    * `config_vars` - hash of configuration variables in lower case (see above)
* `$use_unix_socket = true` - should UNIX sockets be used as much as possible

## type `cfdb::database` parameters
This type must be used only on primary instance of cluster.
**Please avoid direct configuration, see $cfdb::instance::databases**

* `$cluster` - unique cluster name
* `$database` - database name
* `$password = undef` - force password instead of auto-generated for default user
* `$roles = undef` - configuration for extra `cfdb::role` resources (Hiera-friendly).
    * Note: database name is automatically prefixed
* `$ext = []` - database-specific extensions. Genereral format "{name}" or "{name}:{version}".
    If version is omitted then the latest one is used.

Please note that implementation types without concept of databases have a fictional
one defined with the same name as the cluster.

## type `cfdb::instance` parameters
Defines and auto-configures instances.

* `$type` - type of cluster, e.g. elasticsearch, mysql, postgresql
* `$is_cluster = false` - if true, configured instance with cluster in mind
* `$is_secondary = false` - if true, secondary node is assumed
* `$is_bootstrap = false` - if true, forces cluster bootstrap (should be used only TEMPORARY for recovery purposes).
    There is no need to set this during first node of cluster setup since v0.9.9
* `$is_arbitrator = false` - if true, assumes a witness node for quorum with no data
*
* `$memory_weight = 100` - relative memory weight for automatic configuration based on available RAM
* `$memory_max = undef` - max memory the instance can use in auto-configuration
* `$cpu_weight = 100` - relative CPU weight for cgroup isolation
* `$io_weight = 100` - relative I/O weight for cgroup isolation
* `$target_size = 'auto'` - expected database size in bytes (auto - detects based on partition size)
*
* `$settings_tune = {}` - very specific fine tune. See below
* `$databases = undef` - configuration for `cfdb::database` resources
*
* `$iface = $cfdb::iface` - DB network facing interface
* `$cluster_face = $cfdb::cluster_face` - cluster comms network facing interface
* `$port = undef` - force specific network port (mandatory, if `$is_cluster`)
*
* `$backup = $cfdb::backup` - if true, automatic scheduled backup gets enabled
* `$backup_tune = { base_date => 'month' }` - overrides `$type`-specific backup script parameters.
    See below.
*
* `$ssh_key_type = 'ed25519'` - SSH key type for in-cluster communication
* `$ssh_key_bits = 2048` - SSH key bits for RSA
* `$scheduled_actions = {}` - type-specific scheduled actions

## type `cfdb::role` parameters
Define and auto-configures roles per database in specified cluster.
**Please avoid direct configuration, see $cfdb::database::roles**

* `$cluster` - cluster name
* `$database` - database name
* `$password = undef` - force password instead of auto-generated
* `$subname = ''` - role name is equal to $database. Sub-name is added to it.
* `$readonly = false` - set read-only access, if supported by type
* `$custom_grant = undef` - custom grant rules with `$database` and `$user` being replaced
    by actual values.
* `$static_access = {}` - host => maxconn pairs for static configuration with data in PuppetDB.
    **Please avoid using it, unless really needed.**

Please note that if particular implementation is missing concept of databases then there is only
one role with the same name as the cluster.

# Backup & restore

Each instance has `/db/bin/cfdb_{cluster}_backup` and `/db/bin/cfdb_{cluster}_restore` scripts installed to
perform manual backup and manual restore from backup respectively. Of course,
restore will ask to input two different phrases for safety reasons.

There are two types of backup: base and incremental. The type of backup is detected automatically
based on `base_date` option which can be set through `$cfdb::instance::backup_tune`.

Possible values for for `base_date`:
* `'year'` - '%Y'
* `'quarter'` - "%Y-Q$(( $(/bin/date +%m) / 4 + 1 ))"
* `'month'` - '%Y-%m'
* `'week'` - '%Y-W%W'
* `'day'` - '%Y-%m-%d'
* `'daytime'` - '%Y-%m-%d_%H%M%S'
* any accepted as `date` format

If `$cfdb::instance::backup` is true then `bin/cfdb_backup_auto` symlink is created.
The symlinks are automatically called in sequence during system-wide cron-based backup
to **minimize stress on system**.

# TLS tunnel based on HAProxy

As database services do not support a dedicated TLS-only port and generally do not well
offload TLS processing overhead the actual implentation is based on HAProxy utilizing
Puppet PKI for mutual authentication of both peers. There are no changes required
to client application - they open local UNIX socket.

TLS tunnel is created in the following cases:
* `use_proxy = 'secure'` - unconditionally created
* `use_proxy = 'auto'` - if specific database node `cf_location` mismatch client's
    `cf_location`

TLS tunnel is NOT created in the following cases:
* `use_proxy = 'insecure'` - HAProxy is used, but without any TLS security. This parameter
    is useful, if there is lower level secure VPN tunnel is available.
* `use_proxy = false` - HAProxy is not used

# Other commands & configurations

* `/opt/codingfuture/bin/cfdb_backup_all` is installed and used in periodic cron
    for sequential instance backup with minimized stress on the system.
* `/opt/codingfuture/bin/cfdb_access_checker <user> <dotenv> <prefix>` is a generic
    tool to verify each configured access is working. It is used on every Puppet
    provisioning run for every `cfdb::access` defined.
* `/opt/codingfuture/bin/cfdb_restart_pending` is a helper to restart all DB
    instances with pending restart flag

## Elasticsearch

* `/db/bin/cfdb_{cluster}_curl` is installed to properly invoke REST API
* `/db/bin/cfdb_{cluster}_curator` is installed to properly invoke `elasticsearch-curator`

## MongoDB
* `~/.mongorc.js` is properly configured for `mongo` client to work without password in command line or env
* `/db/bin/cfdb_{cluster}_mongo` is installed to properly invoke mongo

## MySQL

* `~/.my.cnf` is properly configured for `mysql` client to work without parameters.
* `/db/bin/cfdb_{cluster}_mysql` is installed to properly invoke mysql
* `/db/bin/cfdb_{cluster}_sysbench` is installed for easy sysbench invocation
* `/db/bin/cfdb_{cluster}_bootstrap` is installed for easy Galera bootstrap

## PostgreSQL

* `/db/bin/cfdb_{cluster}_psql` is installed to properly invoke psql with required parameters.
* `/db/bin/cfdb_{cluster}_repmgr` is installed to properly invoke with required parameters
* `/db/bin/cfdb_{cluster}_vacuumdb` is installed to properly invoke with required parameters
* `~/.pgpass` is properly configured for superuser and repmgr
* `~/.pg_service.conf` is properly configured to be used with `~/bin/cfdb_psql`

## HAProxy

* `/db/bin/cfdb_hatop` is installed to properly invoke hatop


# `$settings_tune` magic

## Elasticsearch

Flat configuration keys in documentation style (no sub-trees). Most of the settings can be
tuned here.

## MongoDB

Flat configuration keys in documentation style (no sub-trees). Most of the settings can be
tuned here.

## MySQL

Quite simple. Every key is section name in MySQL INI. Each value is a hash of section's
variable => value pairs.

*Note: there are some configuration variables which are enforced by CFDB*

However, there is a special `"cfdb"` section, which is interpreted differently. There are
special keys:
* `optimize_ssd` - if true, assume data directory is located on high IOPS hardware
* `secure_cluster` - if true, use Puppet PKI based TLS for inter-node communication
* `shared_secret` - DO NOT USE, for internal cluster purposes.
* `max_connections_roundto = 100` - ceil max_connections to multiple of that
* `listen = 0.0.0.0` - address to listen on, if external connections are detected based
    on `cfdb::access`
* `cluster_listen` - address to listen for cluster communication based on '$cluster_face'
* `inodes_min = 1000` and `inodes_max = 10000` - set gates for automatic calculation of
    `mysqld.table_definition_cache` and `mysqld.table_open_cache`
* `open_file_limit_roundto = 10000` - ceil `mysqld.open_file_limit` to multiple of that
* `binlog_reserve_percent = 10` - percent of $target_size to reserve for binary logs
* `default_chunk_size = 2 * gb` - default for innodb_buffer_pool_chunk_size
* `innodb_buffer_pool_roundto = 1GB or 128MB` - rounding of memory available for InnoDB
    pool. The default depends on actual amount of RAM available.
* `wsrep_provider_options = {}` - overrides for some of `wsrep_provider_options` of Galera Cluster
* `init_db_from` - "{pgver}:{orig_dara_dir}" - copies initial data from specified path
    expecting specific PostgreSQL version and then upgrades
* `joiner_timeout = 600` - how long to wait for initial sync of joiner node



## PostgreSQL

Similar to MySQL. Section named `'postgresql'` overrides some of configuration values in `postgresql.conf`-
some other variables are enforced.

However, there is also a special "cfdb" section:
* `optimize_ssd` - if true, assume data directory is located on high IOPS hardware
* `secure_cluster` - if true, use Puppet PKI based TLS for inter-node communication
* `shared_secret` - DO NOT USE, for internal cluster purposes.
* `strict_hba_roles = true` - if true, hba conf strictly matches each role to host
    instead of using "all" for match. This imitates the same host-based security as
    provided by MySQL.
* `max_connections_roundto = 100` - ceil max_connections to multiple of that
* `listen = 0.0.0.0` - address to listen on, if external connections are detected based
    on `cfdb::access`
* `cluster_listen` - address to listen for cluster communication based on '$cluster_face'
* `inodes_min = 1000` and `inodes_max = 10000` - set gates for automatic calculation of
    `inodes_used` participating in:
    `postgresql.max_files_per_process = 3 * (max_connections + inodes_used)`
* `open_file_limit_roundto = 10000` - ceil `postgresql.max_files_per_process` to multiple of that
* `shared_buffers_percent = 20` - percent of allowed RAM to reserve for shared_buffers
* `temp_buffers_percent = 40` - percent of allowed RAM to reserve for temp_buffers_
* `temp_buffers_overcommit = 8` - ratio of allowed temp_buffers overcommit
* `node_id` - node ID for repmgr. If not set then the last digits of hostname are used as ID.
* `upstream_node_id` - upstream node ID for repmgr. If not set then primary instance is used.
* `locale = 'en_US.UTF-8'` - locale to use for `initdb`
* `init_db_from` - copies initial data dir from specified path and then upgrades

## HAProxy

1. Top level key matches haproxy.conf sections (e.g. global, defaults, frontend XXX, backend YYY, etc.)
    * If section is missing - it is created
2. Top level values must be hashes of section definitions
    * Nil value is interpreted as "delete section"
3. Due to quite messy HAProxy configuration, you should check `lib/puppet/provider/cfdb_haproxy/cfdbb.rb`
    for how to properly overrides entires (some of them include space, like "timeout client")

However, there is also a special "cfdb" section:
* `inter = '3s'` default for `server inter`
* `fastinter = '500ms'` default for `server fastinter` - it also serves for `timeout checks`

# Scheduled actions

## Elasticsearch scheduled actions

All actions are based on `elasticsearch-curator` configuration which is run from cron.

*Note: cron actions run only on cfdb $is_primary node.*

### Old index cleanup

Suitable for cleanup in ELK stack.

* `type = 'cleanup_old'` - must be set exactly
* `prefix` - must be set explicitely (e.g. 'logstash')
* `timestring = '%Y.%m.%d'` - filter.timestring value
* `unit = 'days'` - filter.unit value
* `unit_count = 30` - filter.unit_value value
* `cron = { hour => 2, minute => 10 }` - cron config

### Generic `elasticsearch-curator` actions

* `actions = {}` - as required by curator action config
* `cron = { hour => 2, minute => 10 }` - cron config
