# Change Log

All notable changes to this project will be documented in this file. This
project adheres to [Semantic Versioning](http://semver.org/).

## [0.11.1](https://github.com/codingfuture/puppet-cfdb/releases/tag/v0.11.1)
- Added Puppet 5.x support
- Added Ubuntu Zesty support

## [0.11.0]
- Major refactoring of internals
    - Got rid of facts processing in favor of resources
    - cfdb_access is noy recreated. but only shows error on healthcheck
    - Added a difference between cluster and client interfaces
    - All cluster instances must use the same port now (firewall optimization with ipsets)
    - Switch to cfsystem::clusterssh instead of custom SSH setup
    - Improved of persistent ports & secrets handling based on cfsystem_persist
    - Fixed healthcheck cfdb_access without haproxy case
    - Split DB type-specific features into sub-resources
    - Added obfuscation of password secrets
    - Removed deployment-time secret/port generation in favor on catalog resources (cfsystem)
    - Improved Percona Cluster pre-joining connection check
    - Changed to use ipsets for client list
    - Rewritten cluster healthchecks to use native clients instead of Python scripts
    - Misc. improvements
- Added dependency on cfnetwork:firewall anchor where applicable
- Added dependency on cfsystem::randomfeed for HAProxy dhparam generation
- Updated to new 'cfnetwork::bind_address' API
- Enforced public parameter types
- Updated to work with /etc/sudoers.d cleanup
- Changed default HAProxy inter tune from 1s to 3s (better fits Python-based checkers)
- Added "--skip-version-check" to mysql_upgrade
- Added 'password' parameter for default user of cfdb::database
- Fixed to update superuser & repmgr passwords for postgresql on change
- Aligned with cfnetwork changes for failed DNS resolution
- Added CFDB binary folder to global search path through cfsystem::binpath
- Updated to use gpg trusted key files for Percona due to issues with apt::key @stretch
- Removed deprecated calls to try_get_value()
- Changed to default versions to already installed or latest
- Added warning if configured version mismatches the latest

## [0.10.1]
- Improved to support automatic Galera joiner startup (based on SSH check)
- Changed to filter out Galera arbitrators from normal node gcomm://
- Converted to support Debian/Ubuntu based on LSB versions, but not codenames
- Fixed Debian Stretch support
- Fixed upgrade procedure for standalone MySQL instance
- Updated to cfsystem:0.10.1

## [0.10.0]
- Updated to cfnetwork 0.10.0 API changes
- Fixed puppet-lint issues
- Removed obsolete insecure helper tools under /db/{user}/bin/ -> use /db/bin/
- Minor improvements
- Added per-instance mysqladmin support
- Implemented reload & shutdown for mysqld through mysqladmin
- Added cfdb_restart_pending helper
- Updated CF deps to v0.10.x

## [0.9.16]
- Fixed to properly install repmgr ext with specific postgresql version
- Added installation of new Percona PGP key
- Updated `repmgr` config to use new systemd for control (repmgr 3.2+ is required)
- Improved PostgreSQL upgrade procedures
 > Fixed to ignore init_db_from configuration, if already configured
 > Minor improvements to error handling
 > Fixed to check all slave nodes are down on cluster upgrade
- Upgraded to PostgreSQL 9.6 by default
- Fixed previously introduced bug requiring instance node restart
- Removed 'partman' from default extension list due to incompatibility with PostgreSQL 9.6
- Removed 'pgespresso' as deprecated with PostgreSQL 9.6
- Added `repmgr` arbitrator (`witness`) support (repmgr 3.2+ is required)

## [0.9.15]
- Updated `cfsystem` dependency

## [0.9.14]
- Added automatic cleanup of cfdb instance systemd files
- Security improvement to move root-executed scripts out of DB instance home folders
- Added `cfdb_{cluster}_bootstrap` command support for Galera instances

## [0.9.13]
- Attempt to workaround issue of percona server upgrades requiring
    to shutdown all "mysqld" processes in system

## [0.9.12]
- Fixed to check running cfdbhaproxy
- Updated PXC default to 5.7 (please read official upgrade procedure)
- Changed PXC mysql_upgrade handling to aid official steps
- Minor improvements to secondary server deployment

## [0.9.11]
- Changed to use /dev/urandom for DH params generation to avoid possible
    hang on deployment with low entropy

## [0.9.10]
- Added "cfdb-" prefix to cluster names in automatic global memory management
- Fixed issues in rotational drive auto-detection
- Fixed exception in existing user password check under some circumstances

## [0.9.9]
- Removed need to use is_bootstrap for Galera cluster setup - it's automatic now
- Fixed to check actual in-database passwords for roles for both MySQL and PostgreSQL
- Fixed invalid check of in-database maxconn per PostgreSQL user

## [0.9.8]
- Fixed to workaround Percona bug of missing qpress in Ubuntu repos
- Changed to use Percona Server 5.6 for Ubuntu due to Percona Repo issues

## [0.9.7]
- Removed repack from default PostgreSQL extension list

## [0.9.6]
- Fixed to support init_db_from the same PostgreSQL version

## [0.9.5]
- Changed `cfhaproxy` to `cfdbhaproxy` service name
- Changed internal format of secrets storage
- Updated to new internal features of `cfsystem` module
- Fixed first-run cfdb:access support from actual state with missing facts/resources in PuppetDB
- Added `cfdb::access::use_unix_socket` parameter to control if local TCP connection is required
- Added `maxconn` variable to DB config produced by cfdb::access
- Added `cfdb::role:static_access` support for special cases
- Removed plperl from standard list of extensions as it leads to packaging issues
- Minor changes to interface of `cfdb::access::custom_config`
- Added support for configuring and upgrades PostgreSQL database extensions
- Added automatic cluster status checks in provisioning
- Added initialization from existing location `init_db_from`

## [0.9.4]
- Fixed to support single server access for multiple local users without HAProxy involved
- Added HAProxy `inter` & `fastinter` tune support
- Implemented HAProxy-based secure TLS tunnel for database connection on demand
- Added a workaround for PostgreSQL stats UDP socket
- Added generic /opt/codingfuture/bin/cfdb_access_checker and fixed not to pass access
    password in command line during deployment auto-checks

## [0.9.3]
- Major refactoring to support provider mixins per database type
- Fixed PostgreSQL HBA files with strict_hba_roles 
- Fixed to check that DB services are running
- HAProxy imrovements
    - changed to always use custom cluster-aware health-check scripts
    - changed to use special reverse-proxy socket for health checks
    - changed to support frontend secure connection based on Puppet PKI
    - fixed to properly support PostgreSQL UNIX sockets
- Fixed missing DB variable for .env files
- Added PostgreSQL-specific CONNINFO variable for cfdb::access
- Fixed to properly configure access & max connections on secondary servers
- Implemented automatic check for cfdb::access connection availability
- Fixed issues with roles not getting updated after transition error
- Fixed some cases when PostgreSQL roles were not getting created
- Added support for custom config variable resource for a sort of polymorphism in cfdb::access

## [0.9.2]

Initial release

[0.11.0]: https://github.com/codingfuture/puppet-cfdb/releases/tag/v0.11.0
[0.10.1]: https://github.com/codingfuture/puppet-cfdb/releases/tag/v0.10.1
[0.10.0]: https://github.com/codingfuture/puppet-cfdb/releases/tag/v0.10.0
[0.9.16]: https://github.com/codingfuture/puppet-cfdb/releases/tag/v0.9.16
[0.9.15]: https://github.com/codingfuture/puppet-cfdb/releases/tag/v0.9.15
[0.9.14]: https://github.com/codingfuture/puppet-cfdb/releases/tag/v0.9.14
[0.9.13]: https://github.com/codingfuture/puppet-cfdb/releases/tag/v0.9.13
[0.9.12]: https://github.com/codingfuture/puppet-cfdb/releases/tag/v0.9.12
[0.9.11]: https://github.com/codingfuture/puppet-cfdb/releases/tag/v0.9.11
[0.9.10]: https://github.com/codingfuture/puppet-cfdb/releases/tag/v0.9.10
[0.9.9]: https://github.com/codingfuture/puppet-cfdb/releases/tag/v0.9.9
[0.9.8]: https://github.com/codingfuture/puppet-cfdb/releases/tag/v0.9.8
[0.9.7]: https://github.com/codingfuture/puppet-cfdb/releases/tag/v0.9.7
[0.9.6]: https://github.com/codingfuture/puppet-cfdb/releases/tag/v0.9.6
[0.9.5]: https://github.com/codingfuture/puppet-cfdb/releases/tag/v0.9.5
[0.9.4]: https://github.com/codingfuture/puppet-cfdb/releases/tag/v0.9.4
[0.9.3]: https://github.com/codingfuture/puppet-cfdb/releases/tag/v0.9.3
[0.9.2]: https://github.com/codingfuture/puppet-cfdb/releases/tag/v0.9.2

