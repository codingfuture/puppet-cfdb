# Change Log

All notable changes to this project will be documented in this file. This
project adheres to [Semantic Versioning](http://semver.org/).

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

[0.9.8]: https://github.com/codingfuture/puppet-cfdb/releases/tag/v0.9.8
[0.9.7]: https://github.com/codingfuture/puppet-cfdb/releases/tag/v0.9.7
[0.9.6]: https://github.com/codingfuture/puppet-cfdb/releases/tag/v0.9.6
[0.9.5]: https://github.com/codingfuture/puppet-cfdb/releases/tag/v0.9.5
[0.9.4]: https://github.com/codingfuture/puppet-cfdb/releases/tag/v0.9.4
[0.9.3]: https://github.com/codingfuture/puppet-cfdb/releases/tag/v0.9.3
[0.9.2]: https://github.com/codingfuture/puppet-cfdb/releases/tag/v0.9.2

