
# Done this way due to some weird behavior in tests also ignoring $LOAD_PATH
begin
    require File.expand_path( '../../cf_system/provider_base', __FILE__ )
rescue LoadError
    require File.expand_path( '../../../../../cfsystem/lib/puppet_x/cf_system/provider_base', __FILE__ )
end


module PuppetX::CfDb
    class ProviderBase < PuppetX::CfSystem::ProviderBase
        def self.mixin_dbtypes(prov_type)
            @version_files = [__FILE__]
            @version_files << "#{BASE_DIR}/../puppet/provider/cfdb_#{prov_type}/cfdb.rb"
            
            CFDB_TYPES.each do |t|
                self.extend(PuppetX::CfDb.const_get(t).const_get(prov_type.capitalize))
                @version_files << "#{BASE_DIR}/cf_db/#{t.downcase}/#{prov_type.downcase}.rb"
            end
        end
        
        def self.get_generator_version
            cf_system().makeVersion(@version_files)
        end
    end
end