#
# Copyright 2016-2018 (c) Andrey Galkin
#


require 'fileutils'

require File.expand_path( '../../../../puppet_x/cf_db', __FILE__ )

Puppet::Type.type(:cfdb_instance).provide(
    :cfdb,
    :parent => PuppetX::CfDb::ProviderBase
) do
    desc "Provider for cfdb_instance"
    
    mixin_dbtypes('instance')
    
    commands :sudo => PuppetX::CfSystem::SUDO
    commands :systemctl => PuppetX::CfSystem::SYSTEMD_CTL
    commands :df => '/bin/df'
    commands :du => '/usr/bin/du'

    def self.get_config_index
        'cf10db1_instance'
    end
    
    def self.check_exists(params)
        debug('check_exists')
        begin
            check_res = File.exists?(params[:root_dir] + '/data') and
                    systemctl(['status', "#{params[:service_name]}.service"])
            
            db_type = params[:type]
            self.send("check_cluster_#{db_type}", params)
            
            check_res
        rescue => e
            warning(e)
            #warning(e.backtrace)
            false
        end
    end
   
    def self.on_config_change(newconf)
        debug('on_config_change')
        
        @new_services = []
        @new_slices = []
        
        newconf.each do |name, conf|
            db_type = conf[:type]
            
            begin
                self.send("create_#{db_type}", conf)
            rescue => e
                warning(e)
                #warning(e.backtrace)
                err("Transition error in setup")
            end
        end
        
        begin
            prefix = PuppetX::CfDb::CFDB_TYPES.join(',').downcase
            cf_system.cleanupSystemD("cf{#{prefix}}-", @new_services)
            cf_system.cleanupSystemD('system-cfdb_', @new_slices, 'slice')
        rescue => e
            warning(e)
            warning(e.backtrace)
            err("Transition error in setup")
        end
    end
    
    def self.fit_range(min, max, val)
        return cf_system.fitRange(min, max, val)
    end
    
    def self.round_to(to, val)
        return cf_system.roundTo(to, val)
    end
    
    def self.get_memory(cluster)
        cf_system.getMemory("cfdb-#{cluster}")
    end
    
    def self.create_service(conf, service_ini, service_env, slice_name = nil, service_name = nil)
        db_type = conf[:type]
        service_name = conf[:service_name] if service_name.nil?
        user = conf[:user]
        
        mem_limit = get_memory(conf[:cluster])
        
        #---
        content_env = {
            'CFDB_ROOT_DIR' => conf[:root_dir],
        }
        
        content_env.merge! service_env
        
        #---
        content_ini = {
            'Unit' => {
                'Description' => "CFDB instance: #{service_name}",
            },
            'Service' => {
                'LimitNOFILE' => 100000,
                'WorkingDirectory' => conf[:root_dir],
            },
        }
        
        content_ini['Service'].merge! service_ini
        
        #---
        opts = {
            :service_name => service_name,
            :user => user,
            :content_ini => content_ini,
            :content_env => content_env,
        }
        
        if slice_name.nil?
            opts.merge!({
                :cpu_weight => conf[:cpu_weight],
                :io_weight => conf[:io_weight],
                :mem_limit => mem_limit,
                :mem_lock => true,
            })
        else
            content_ini['Service']['Slice'] = "#{slice_name}.slice"
        end
        
        #---
        @new_services << service_name
        self.cf_system().createService(opts)
    end
    
    def self.create_slice(slice_name, conf)
        mem_limit = get_memory(conf[:cluster])
        self.cf_system().createSlice({
            :slice_name => slice_name,
            :cpu_weight => conf[:cpu_weight],
            :io_weight => conf[:io_weight],
            :mem_limit => mem_limit,
        })
        @new_slices << slice_name
    end
    
    def self.disk_size(dir)
        ret = df('-BM', '--output=size', dir)
        ret = ret.split("\n")
        ret[1].strip().to_i
    end
    
    def self.is_low_iops(dir)
        ret = df('-BM', '--output=source', dir)
        ret = ret.split("\n")
        device = ret[1].strip()
        
        if not File.exists?(device)
            debug("Device not found #{device}")
            # assume something with high IOPS
            return false
        end
        
        if File.symlink?(device)
            device = File.readlink(device)
        end
        
        device = File.basename(device)
        
        begin
            device = "/sys/block/#{device}"
            
            if not File.exists? device
                device.gsub!(/[0-9]/, '')
            end
            
            rotational = File.read("#{device}/queue/rotational").to_i
            debug("Device #{device} rotational = #{rotational}")
            return rotational.to_i == 1
        rescue => e
            warning(e)
             # assume something with high IOPS
            return false
        end
    end
    
    def self.wait_sock(service_name, sock_file, timeout=60)
        PuppetX::CfSystem::Util.wait_sock(service_name, sock_file, timeout)
    end
end
