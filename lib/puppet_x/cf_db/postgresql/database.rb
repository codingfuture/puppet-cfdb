
module PuppetX::CfDb::PostgreSQL::Database
    include PuppetX::CfDb::PostgreSQL
    
    def create_postgresql(user, database, root_dir)
        return if check_postgresql(user, database, root_dir)
        sudo("#{root_dir}/bin/cfdb_psql",
             '--tuples-only', '--no-align', '--quiet',
             '-c', "CREATE DATABASE #{database} TEMPLATE template0;")
    end
    
    def check_postgresql(user, database, root_dir)
        ret = sudo(
            "#{root_dir}/bin/cfdb_psql",
            '--tuples-only', '--no-align', '--quiet',
            '-c', "SELECT datname FROM pg_database WHERE datname = '#{database}';"
        )
        not ret.empty?
    end
end
