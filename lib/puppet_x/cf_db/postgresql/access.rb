
module PuppetX::CfDb::PostgreSQL::Access
    include PuppetX::CfDb::PostgreSQL
    
    def check_postgresql(local_user, config_vars)
        sudo('-H', '-u', local_user,
             PSQL, config_vars['conninfo'],
             '-c', 'SELECT 1;',
             '--tuples-only', '--no-align', '--quiet')
    end
end
