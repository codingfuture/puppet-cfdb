
module PuppetX::CfDb::MySQL::Database
    include PuppetX::CfDb::MySQL
    
    def create_mysql(user, database, root_dir)
        return if check_mysql(user, database, root_dir)
        sudo('-H', '-u', user, MYSQLADMIN, 'create', database)
    end
    
    def check_mysql(user, database, root_dir)
        ret = sudo('-H', '-u', user, MYSQL, '--wait', '-e', "SHOW DATABASES LIKE '#{database}';")
        not ret.empty?
    end
end
