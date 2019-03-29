#
# Copyright 2019 (c) Andrey Galkin
#

module PuppetX::CfDb::Redis::Role
    include PuppetX::CfDb::Redis
    
    def create_redis(cluster_user, conf, root_dir)
        check_redis(cluster_user, conf, root_dir, true)
    end
    
    def check_redis(cluster_user, conf, root_dir, update=false)
        instance_index = Puppet::Type.type(:cfdb_instance).provider(:cfdb).get_config_index
        inst_conf = cf_system().config.get_new(instance_index)
        cluster = conf[:cluster]
        
        inst_conf = inst_conf[cluster]
        return false if inst_conf.nil?

        root_pass = inst_conf[:settings_tune].fetch('cfdb', {}).fetch('shared_secret', '')
        
        if conf[:password] != root_pass
            return false if !update

            persistent = cf_system().config.get_persistent_all

            # a small hack
            assoc_id = "cfdb/#{cluster}@#{conf[:user]}"
            persistent['secrets'][assoc_id] = root_pass

            conf[:password] = root_pass
        end
        
        return true
    end
end
