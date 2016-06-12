
module PuppetX::CfDb::MySQL::Access
    include PuppetX::CfDb::MySQL
    
    def check_mysql(local_user, config_vars)
        port = config_vars['port']
        port = 1 if port.empty?
        
        socket = config_vars['socket']
        socket = '/notexisting.sock' if socket.empty?
        
        # TODO: get rid of password on commandline
        
        sudo('-H', '-u', local_user,
             MYSQL,
             "--user=#{config_vars['user']}",
             "--password=#{config_vars['pass']}",
             "--host=#{config_vars['host']}",
             "--port=#{port}",
             "--socket=#{socket}",
             '--batch', '-e', 'SELECT 1;'
        )
    end
end
