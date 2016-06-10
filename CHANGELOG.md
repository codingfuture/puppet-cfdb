# Change Log

All notable changes to this project will be documented in this file. This
project adheres to [Semantic Versioning](http://semver.org/).

## [0.9.1]
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

## [0.9.0]

Initial release

[0.9.1]: https://github.com/codingfuture/puppet-cfdb/releases/tag/v0.9.1
[0.9.0]: https://github.com/codingfuture/puppet-cfdb/releases/tag/v0.9.0

