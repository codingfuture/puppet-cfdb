#!/usr/bin/env python
#--------------------------------------
# This script is designed:
# 1. to avoid password passing in paramters or env
# 2. to imitate real client application for CFDB access checks
#--------------------------------------

import os, sys, pwd, re

if len(sys.argv) != 4:
    print("Usage: {0} <user> <dot-env-file> <variable-prefix>".format(sys.argv[0]))
    sys.exit(1)

user =  sys.argv[1]
dotenv = sys.argv[2]
var_prefix = sys.argv[3]

user_info = pwd.getpwnam(user)

# Drop root
#---
if os.geteuid() != user_info.pw_uid:
    os.setegid(user_info.pw_gid)
    os.seteuid(user_info.pw_uid)

# Change to home
#---
os.chdir(user_info.pw_dir)

# Parse file
#---
var_re = re.compile('^\s*([a-zA-Z0-9_-]+)\s*=\s*(("([^"]*)")|([^#]*))')
conf = {}
with open(dotenv, "r") as f:
    for line in f:
        m = var_re.match(line)
        if not m: continue

        var = m.group(1)

        if m.group(4) is not None:
            val = m.group(4).decode('string_escape')
        else:
            val = m.group(5).strip()

        conf[var] = val

# Verify connection
#---
def getconf(name):
    var = var_prefix + name

    if var not in conf:
        print("ERROR: {0} is missing from {1}".format(var, dotenv))
        sys.exit(1)

    return conf[var]

db_type = getconf('TYPE')

if db_type == 'mysql':
    import MySQLdb
    conn_params={
        'db': getconf('DB'),
        'user': getconf('USER'),
        'passwd': getconf('PASS'),
        'host': getconf('HOST'),
        'port': int(getconf('PORT')),
        'unix_socket': getconf('SOCKET'),
        'connect_timeout': 2,
    }

    try:
        conn = MySQLdb.connect(**conn_params)
    except:
        conn = MySQLdb.connect(**conn_params)

    curs = conn.cursor()
    curs.execute('SELECT 1;')
    conn.close()

elif db_type == 'postgresql':
    import psycopg2

    host = getconf('HOST')

    if host == 'localhost':
        host = getconf('SOCKET')

    conn_params={
        'database': getconf('DB'),
        'user': getconf('USER'),
        'password': getconf('PASS'),
        'host': host,
        'port': int(getconf('PORT')),
        'connect_timeout': 2,
    }

    try:
        conn = psycopg2.connect(**conn_params)
    except:
        conn = psycopg2.connect(**conn_params)

    curs = conn.cursor()

    curs = conn.cursor()
    curs.execute('SELECT 1;')
    conn.close()

elif db_type == 'elasticsearch':
    try:
        import httplib as client
    except ImportError:
        import http.client as client

    conn = client.HTTPConnection( getconf('HOST'), getconf('PORT'), timeout=3 )
    conn.request( 'GET', '/_cluster/health?local' )
    res = conn.getresponse()

    if res.status != 200:
        print( "ERROR: not OK '{0}'".format(res.status) )
        sys.exit(1)

    res = res.read()
    conn.close()

    import json
    res = json.loads(res)

    if res['status'] == 'red':
        print( "ERROR: red status" )
        sys.exit(1)
else:
    print("ERROR: unknown database type '{0}'".format(db_type))
    sys.exit(1)

#---
print('OK')
sys.exit(0)
