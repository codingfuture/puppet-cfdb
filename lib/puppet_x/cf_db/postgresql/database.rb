#
# Copyright 2016-2018 (c) Andrey Galkin
#


module PuppetX::CfDb::PostgreSQL::Database
    include PuppetX::CfDb::PostgreSQL
    
    def get_available_pgext(database, root_dir)
        ext_list_raw = sudo(
            "#{root_dir}/bin/cfdb_psql",
            '--tuples-only', '--no-align', '--quiet',
            '--field-separator=,',
            '-d', database,
            '-c', "SELECT name, installed_version, default_version " +
                  "FROM pg_available_extensions;"
        )
        
        ext_list = {}
        ext_list_raw.split("\n").each do |l|
            extname, installed, default_version = l.split(',')
            ext_list[extname] = {
                :installed => installed,
                :default => default_version
            }
        end
        
        return ext_list
    end
    
    def create_postgresql(user, database, root_dir, params)
        return if check_postgresql(user, database, root_dir, params)
        
        if not @check_dbexists
            warning(">> creating db #{database}")
            sudo("#{root_dir}/bin/cfdb_psql",
                '--tuples-only', '--no-align', '--quiet',
                '-c', "CREATE DATABASE #{database} TEMPLATE template0;")
        end
        
        ext = params[:ext]
        return true if ext.nil? or ext.empty?
        
        #---
        ext_list = get_available_pgext(database, root_dir)
        
        ext.each do |extname|
            extname, extver = extname.split(':')
            
            installed = ext_list.fetch(extname, {})[:installed]
            extver = ext_list.fetch(extname, {})[:default] if extver.nil?
            
            if installed.nil? or installed.empty?
                warning(">> creating ext #{extname}:#{extver} in #{database}")
                sudo("#{root_dir}/bin/cfdb_psql",
                    '--tuples-only', '--no-align', '--quiet',
                    '-d', database,
                    '-c', "CREATE EXTENSION #{extname} VERSION '#{extver}';"
                )
            elsif installed != extver
                warning(">> updating ext #{extname}:#{extver} in #{database}")
                sudo("#{root_dir}/bin/cfdb_psql",
                    '--tuples-only', '--no-align', '--quiet',
                    '-d', database,
                    '-c', "ALTER EXTENSION #{extname} UPDATE TO '#{extver}';"
                )
            end
        end
    end
    
    def check_postgresql(user, database, root_dir, params)
        @check_dbexists = false
        ret = sudo(
            "#{root_dir}/bin/cfdb_psql",
            '--tuples-only', '--no-align', '--quiet',
            '-c', "SELECT datname FROM pg_database WHERE datname = '#{database}';"
        )
        return false if ret.empty?
        @check_dbexists = true
        
        ext = params[:ext]
        return true if ext.nil? or ext.empty?
        
        #---
        ext_list = get_available_pgext(database, root_dir)
        
        ext.each do |extname|
            extname, extver = extname.split(':')
            installed = ext_list.fetch(extname, {})[:installed]
            extver = ext_list.fetch(extname, {})[:default] if extver.nil?
            return false if installed != extver
        end
    end
end
