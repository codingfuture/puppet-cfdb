#
# Copyright 2018-2019 (c) Andrey Galkin
#


module PuppetX::CfDb::Elasticsearch::Database
    include PuppetX::CfDb::Elasticsearch
    
    
    def create_elasticsearch(user, database, root_dir, params)
        true
    end
    
    def check_elasticsearch(user, database, root_dir, params)
        true
    end
end
