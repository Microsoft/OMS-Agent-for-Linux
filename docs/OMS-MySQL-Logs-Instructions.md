# MySQL Server Log Monitoring Solution for Operations Management Suite

1. Setup a supported Linux machine and install [MySQL](https://docs.microsoft.com/en-us/azure/virtual-machines/linux/mysql-install).

2. Download and Install [OMS Agent for Linux](https://github.com/Microsoft/OMS-Agent-for-Linux) on the machine.

3. You can get the workspace ID for your machine from the OMS portal after it has onboarded successfully.

  Go to Settings -> Connected Sources -> Linux Servers
  ![OMSPortalWorkspaceID](pictures/OMSPortalWorkspaceID.PNG?raw=true)

4. Configure MySQL to generate [slow](http://dev.mysql.com/doc/refman/5.7/en/slow-query-log.html), [error](http://dev.mysql.com/doc/refman/5.7/en/error-log.html), and [general](http://dev.mysql.com/doc/refman/5.7/en/query-log.html) logs.

5. Verify and update the MySQL log file path in the configuration file `/etc/opt/microsoft/omsagent/<workspace id>/conf/omsagent.d/mysql_logs.conf`  
If `mysql_logs.conf` is not present in the above location, move it:  
`sudo cp /etc/opt/microsoft/omsagent/sysconf/omsagent.d/mysql_logs.conf /etc/opt/microsoft/omsagent/<workspace id>/conf/omsagent.d/`  
`sudo chown omsagent:omiusers /etc/opt/microsoft/omsagent/<workspace id>/conf/omsagent.d/mysql_logs.conf`

  ```config
  # MySQL General Log

  <source>
    ...
    path <MySQL-file-path-for-general-logs>
    ...
  </source>

  # MySQL Error Log

  <source>
    ...
    path <MySQL-file-path-for-error-logs>
    ...
  </source>

  # MySQL Slow Query Log

  <source>
    ...
    path <MySQL-file-path-for-slow-query-logs>
    ...
  </source>
  ```

6. Restart the MySQL daemon:
`sudo service mysql restart` or `/etc/init.d/mysqld restart`

7. Restart the OMS agent:
`sudo /opt/microsoft/omsagent/bin/service_control restart`


8. Confirm that there are no errors in the OMS Agent log:  
`tail /var/opt/microsoft/omsagent/<workspace id>/log/omsagent.log`

  If you encounter the following (or a similar) error in `omsagent.log`:  
  `[error]: Permission denied @ rb_sysopen - <MySQL-file-path-for-logs>`

  1. Ensure that the user `omsagent` has read and execute permissions on the parent directory and read permissions contained log files:  
  `chmod +r <MySQL-file-path-for-logs>`  
  `chmod +rx <folder-containing-MySQL-logs>`

  2. If your machine has logrotate enabled, the new log files that get rotated in may cause this error to resurface. Check the logrotate configuration file (e.g. `/etc/logrotate.d/mysql-server`) for the permissions it assigns new log files. To ensure that the user `omsagent` has read permissions on newly-created log files, here are two options:

    1. Identify the file group for the log files, and add the user `omsagent` to the file group:
    ```commands
    ls -l <MySQL-file-path-for-slow-query-logs>
    usermod -aG <file-group> omsagent
    ```  

    2. Modify the logrotate configuration file to assign new log files read permissions to all users:  
    Change `create 640 mysql adm` to `create 644 mysql adm`

  3. After changing file permissions, the OMS agent should be restarted:  
  `sudo /opt/microsoft/omsagent/bin/service_control restart`

  If you encounter either of the following in `omsagent.log`, these warnings can safely be ignored:  
  `[warn]: pattern not match: ...`  
  `[warn]: got incomplete line ...`

9. Go to OMS Log Search and see whether you can find any results:
![MySQLSearchView](pictures/MySQLSearchView.PNG?raw=true)

# MySQL Server Custom Metrics Monitoring Solution for Operations Management Suite

If you want to know more about internal metrics of your MySQL instance you can take advantage of the OMS json output and configure it as:

1. Open the file `/etc/opt/microsoft/omsagent/<workspace id>/conf/omsagent.d/mysql_logs.conf` and append the following configuration, don't foget to update with your workspace ID:


```
# Custom info

<source>
  type exec
  command '/usr/local/bin/mysql_info.py'
  format json
  tag oms.api.MySQL.info
  run_interval 30s
</source>

<match oms.api.MySQL.info>
  type out_oms_api
  log_level info

  buffer_chunk_limit 5m
  buffer_type file
  buffer_path /var/opt/microsoft/omsagent/<workspace id>/state/out_oms_api_mysqlinfo*.buffer
  buffer_queue_limit 10
  flush_interval 20s
  retry_limit 10
  retry_wait 30s
</match>

<match oms.api.**>
  type out_oms_api
  log_level info

  buffer_chunk_limit 5m
  buffer_type file
  buffer_path /var/opt/microsoft/omsagent/<workspace id>/state/out_oms_api*.buffer
  buffer_queue_limit 10
  flush_interval 20s
  retry_limit 10
  retry_wait 30s
</match>
```

Here is a sample of mysql_info.py script:

![mysql_info.py](code_sample/mysql_info.py)


2. Ensure that the user `omsagent` has read and execute permissions on the script file:  
`chmod +x /usr/local/bin/mysql_info.py`  

Output:
```
{"active_connections": 12}
```


3. Restart the OMS agent:
`sudo /opt/microsoft/omsagent/bin/service_control restart`

Check the logs for any outstanding error:
`tail -f /var/opt/microsoft/omsagent/<workspace id>/log/omsagent.log`

4. Go to OMS Log Search and see whether you can find any results:

```
// MySQL active connections
MySQL_CL 
| project TimeGenerated, active_connections_d
| render timechart
```

![MySQLSearchView](pictures/Azure_Log_Analytics_onprem_MySQL_Dashboard.png?raw=true)
