#
# Copyright 2019 (c) Andrey Galkin
#


module PuppetX::CfDb::Redis::Database
    include PuppetX::CfDb::Redis
    
    def create_redis(user, database, root_dir, params)
        true
    end
    
    def check_redis(user, database, root_dir, params)
        true
    end
end
