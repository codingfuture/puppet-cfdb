
module PuppetX::CfDb::MySQL
    ROOT_PASS_LEN = PuppetX::CfDb::ROOT_PASS_LEN
    MYSQL = '/usr/bin/mysql'
    MYSQLADMIN = '/usr/bin/mysqladmin'
    MYSQLD = '/usr/sbin/cfmysqld'
    MYSQL_INSTALL_DB = '/usr/bin/mysql_install_db'
    MYSQL_UPGRADE = '/usr/bin/mysql_upgrade'
    GARBD = '/usr/bin/garbd'
    
    GALERA_PORT_OFFSET = 100
    SST_PORT_OFFSET = 200
    IST_PORT_OFFSET = 300
end