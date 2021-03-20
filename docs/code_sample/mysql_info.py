#!/usr/bin/env python3
# Create or update your MySQL readonly user:
# GRANT SELECT on DBNAME.* to 'readonlyuser'@'%' identified by '*Super-Secr3t-r0*';
# GRANT SELECT, PROCESS ON *.* TO 'readonlyuser'@'localhost';

import json
import subprocess

dbuser='readonlyuser'
dbpasswd='*Super-Secr3t-r0*'
database='information_schema'
mycmd='mysql --batch --skip-column-names -u%s -p\'%s\' -D %s -e \'show processlist\' | wc -l' % (dbuser, dbpasswd, database)

def mysql_info():
    try:
        cmdrs = subprocess.check_output(mycmd, shell=True).rstrip()

        response = {
                        "active_connections": int(cmdrs)
                    }

        return print(json.dumps(response))

    except Exception as err:
        err = {"error": err}

        return print(json.dumps(err))

mysql_info()
