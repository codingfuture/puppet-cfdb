
require 'ipaddr'
require 'resolv'

require File.expand_path( '../../../../puppet_x/cf_db', __FILE__ )

Puppet::Type.type(:cfdb_role).provide(
    :cfdb,
    :parent => PuppetX::CfDb::ProviderBase
) do
    desc "Provider for cfdb_role"
    
    mixin_dbtypes('role')
    
    commands :sudo => '/usr/bin/sudo'
    
    class << self
        # cfsystem.json config state
        # { cluster_user => { user => orig_params }
        attr_accessor :role_old
        # actual DB server config state
        # { cluster_user => { user => { allowed_hosts => max_connections } } }
        attr_accessor :role_cache
    end
    self.role_old = {}
    self.role_cache = {}
    
    def flush
        super
        title = "#{@resource[:cluster]}@#{@resource[:database]}"
        cf_system().config.get_persistent('cfdb_passwd')[title] = @resource[:password]
    end
    
    def self.check_exists(params)
        debug('check_exists')
        begin
            instance_index = Puppet::Type.type(:cfdb_instance).provider(:cfdb).get_config_index
            inst_conf = cf_system().config.get_old(instance_index)
            cluster = params[:cluster]
            
            inst_conf = inst_conf[cluster]
            return false if inst_conf.nil?
            
            cluster_user = inst_conf['user']
            db_type = inst_conf['type']
            root_dir = inst_conf['root_dir']
            
            self.role_old[cluster_user] = {} if not self.role_old.has_key? cluster_user
            self.role_old[cluster_user][params[:user]] = params
            
            begin
                self.send("check_#{db_type}", cluster_user, params, root_dir)
            rescue => e
                warning(e)
                #warning(e.backtrace)
                err("Transition error in setup")
            end
        rescue => e
            warning(e)
            #warning(e.backtrace)
            false
        end

    end
    
    def self.get_config_index
        'cf10db3_role'
    end
    
    def self.on_config_change(newconf)
        debug('on_config_change')
        to_delete = self.role_cache.clone
        
        instance_index = Puppet::Type.type(:cfdb_instance).provider(:cfdb).get_config_index
        inst_conf_all = cf_system().config.get_new(instance_index)
        
        cluster_delinfo = {}
        
        newconf.each do |k, conf|
            cluster_name = conf[:cluster]
            inst_conf = inst_conf_all[cluster_name]
            cluster_user = inst_conf[:user]
            db_type = inst_conf[:type]
            root_dir = inst_conf[:root_dir]
            
            begin
                self.send("create_#{db_type}", cluster_user, conf, root_dir)
            rescue => e
                warning(e)
                #warning(e.backtrace)
                err("Transition error in setup")
            end
            
            if to_delete.has_key? cluster_user
                to_delete[cluster_user].delete conf[:user]
                cluster_delinfo[cluster_user] = {
                    :db_type => db_type,
                    :root_dir => root_dir,
                }
            end
        end
        
        to_delete.each do |cluster_user, cache|
            cinfo = cluster_delinfo[cluster_user]
            db_type = cinfo[:db_type]
            
            cache.each do |user, v|
                self.send("create_#{db_type}", cluster_user,
                {
                    :user => user,
                    :password => nil,
                    :allowed_hosts => {}
                }, cinfo[:root_dir])
            end
        end
    end
    
    def self.check_match_common(cluster_user, conf)
        user = conf[:user]
        oldconf = self.role_old.fetch(cluster_user, {}).fetch(user, nil)
        
        return false if oldconf.nil?
        return false if oldconf.fetch(:custom_grant, nil) != conf[:custom_grant]
        return false if oldconf.fetch(:readonly, nil) != conf[:readonly]
        return false if oldconf.fetch(:database, nil) != conf[:database]
        return false if oldconf.fetch(:custom_grant, nil) != conf[:custom_grant]
        
        true
    end
end
