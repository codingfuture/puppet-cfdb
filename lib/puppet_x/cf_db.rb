
module PuppetX::CfDb
    CFDB_TYPES = [
        'MySQL',
        'PostgreSQL'
    ]
    ROOT_PASS_LEN = 24
    BASE_DIR = File.expand_path('../', __FILE__)

    #---
    require "#{BASE_DIR}/cf_db/provider_base"
    
    CFDB_TYPES.each do |t|
        t = t.downcase()
        require "#{BASE_DIR}/cf_db/#{t}"
        require "#{BASE_DIR}/cf_db/#{t}/database"
        require "#{BASE_DIR}/cf_db/#{t}/instance"
        require "#{BASE_DIR}/cf_db/#{t}/role"
    end
end
