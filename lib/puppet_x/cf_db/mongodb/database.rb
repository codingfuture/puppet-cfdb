#
# Copyright 2019 (c) Andrey Galkin
#


module PuppetX::CfDb::MongoDB::Database
    include PuppetX::CfDb::MongoDB
    
    
    def create_mongodb(user, database, root_dir, params)
        true
    end
    
    def check_mongodb(user, database, root_dir, params)
        true
    end
end
