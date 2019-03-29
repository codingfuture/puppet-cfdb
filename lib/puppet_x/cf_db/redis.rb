#
# Copyright 2019 (c) Andrey Galkin
#


module PuppetX::CfDb::Redis
    ROOT_PASS_LEN = PuppetX::CfDb::ROOT_PASS_LEN

    SENTINEL_OFFSET = 100

    REDIS_CLI = '/usr/bin/redis-cli'
    REDIS_SERVER = '/usr/bin/redis-server'
    REDIS_SENTINEL = '/usr/bin/redis-sentinel'
end
