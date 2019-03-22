#
# Copyright 2018-2019 (c) Andrey Galkin
#


module PuppetX::CfDb::Elasticsearch::Role
    include PuppetX::CfDb::Elasticsearch
    
    def create_elasticsearch(cluster_user, conf, root_dir)
        true
    end
    
    def check_elasticsearch(cluster_user, conf, root_dir)
        true
    end
end
