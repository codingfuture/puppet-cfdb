#
# Copyright 2016 (c) Andrey Galkin
#


module PuppetX::CfDb::MySQL::Database
    include PuppetX::CfDb::MySQL
    
    def create_mysql(user, database, root_dir, params)
        return if check_mysql(user, database, root_dir, params)
        sudo('-H', '-u', user, MYSQLADMIN, 'create', database)
    end
    
    def check_mysql(user, database, root_dir, params)
        ret = sudo('-H', '-u', user, MYSQL, '--wait', '-e', "SHOW DATABASES LIKE '#{database}';")
        not ret.empty?
    end
end
