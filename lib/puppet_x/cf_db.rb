#
# Copyright 2016 (c) Andrey Galkin
#


# Done this way due to some weird behavior in tests also ignoring $LOAD_PATH
begin
    require File.expand_path( '../cf_system', __FILE__ )
rescue LoadError
    require File.expand_path( '../../../../cfsystem/lib/puppet_x/cf_system', __FILE__ )
end


module PuppetX::CfDb
    CFDB_TYPES = [
        'MySQL',
        'PostgreSQL'
    ]
    ROOT_PASS_LEN = 24
    BASE_DIR = File.expand_path('../', __FILE__)
    SECURE_PORT_OFFSET = 50
    ACCESS_CHECK_TOOL = "#{PuppetX::CfSystem::CUSTOM_BIN_DIR}/cfdb_access_checker"

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
