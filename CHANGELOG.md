# Change Log

All notable changes to this project will be documented in this file. This
project adheres to [Semantic Versioning](http://semver.org/).

## [0.9.4]
- Fixed to support single server access for multiple local users without HAProxy involved
- Added HAProxy `inter` & `fastinter` tune support

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

[0.9.4]: https://github.com/codingfuture/puppet-cfdb/releases/tag/v0.9.4
[0.9.3]: https://github.com/codingfuture/puppet-cfdb/releases/tag/v0.9.3
[0.9.2]: https://github.com/codingfuture/puppet-cfdb/releases/tag/v0.9.2

