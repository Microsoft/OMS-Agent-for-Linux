# Configuration for collection of Fortinet Fortigate logs (Preview)

**This feature is part of the OMS Security and Audit solution. The solution needs to be enabled before the events can be collected.**

Collection of the following 3rd party security log types is supported:
- **Fortinet Fortigate logs FortiOS < 5.6**

Fortinet Fortigate can send events in CEF starting from [FortiOS 5.6](http://help.fortinet.com/fos50hlp/56/Content/FortiOS/fortigate-whats-new/Top-LogReport-cef.htm?Highlight=syslog%20CEF), if it is not possibile to update the appliances to the new OS, this solution can be used to translate legacy Fortigate Logs in CEF and ingest them into Log Analytics.

## Caveats

Fortigate log parsing can have an impact on CPU utilization by the OMS agent, the solution has been tested on a dual core Virtual Machine ingesting about 40 events per second causing an increase in CPU usage of about 5%.

## Configuration summary
1. Install and onboard the OMS Agent for Linux
2. Configure Syslog forwarding to send the required logs to the agent on UDP port 25227. This must be a dedicated syslog to be able to differentiatte >Fortigate logs from other log types
3. Place the agent configuration [file][1] on the agent machine in ```/etc/opt/microsoft/omsagent/<workspace id>/conf/omsagent.d/```
4. Restart the syslog daemon and the OMS agent


## Detailed configuration
1. Download the OMS Agent for Linux, version 1.2.0-25 or above
    - [OMS Agent for Linux GA v1.2.0-25](https://github.com/Microsoft/OMS-Agent-for-Linux/releases/tag/OMSAgent_GA_v1.2.0-25)

2. Install and onboard the agent to your workspace as described here:
    - [Documentation for OMS Agent for Linux](https://github.com/Microsoft/OMS-Agent-for-Linux)  

3. Send the required logs to the OMS Agent for Linux
    * Typically the agent is installed on a different machine from the one on which the logs are generated. Forwarding the logs to the agent machine will usually require several steps:
        1. Configure the logging product/machine to forward the required events to the syslog daemon (e.g. rsyslog or syslog-ng) on the agent machine.
        2. Enable the syslog daemon on the agent machine to receive messages from a remote system.
	    
    * On the agent machine, the events need to be sent from the syslog daemon to a local UDP port. Use [this guide](https://github.com/Microsoft/OMS-Agent-for-Linux/blob/master/docs/OMS-Agent-for-Linux.md#syslog-troubleshooting) to check for available ports; in this example, we use UDP port 25227.
        *The following is an example configuration for sending all events from the local3 facility to the agent. You can modify the configuration to fit your local settings.* 
	
        **If the agent machine has an rsyslog daemon:**  
        In directory ```/etc/rsyslog.d/```, create new file ```security-config-omsagent.conf``` with the following content:

        ```
        #OMS_facility = local3
        local3.debug       @127.0.0.1:25227
        ```
	
        **If the agent machine has a syslog-ng daemon:**  
	    In directory ``` /etc/syslog-ng/```, create new file ```security-config-omsagent.conf``` with the following content:

        ```
        #OMS_facility = local3  
        filter f_local3_oms { facility(local3); };  
        destination security_oms { tcp("127.0.0.1" port(25227)); };  
        log { source(src); filter(f_local3_oms); destination(security_oms); };  
        ```

4. Place the following configuration file on the OMS Agent machine:  
  	- [fortigate_events.conf][1]  
  	_Fluentd configuration file to enable collection and parsing of the events_  
	Destination path on Agent machine: ```/etc/opt/microsoft/omsagent/<workspace id>/conf/omsagent.d/```  

5. Restart the syslog daemon:  
```sudo service rsyslog restart``` or ```sudo /etc/init.d/syslog-ng restart```

6. Restart the OMS Agent:  
```sudo /opt/microsoft/omsagent/bin/service_control restart```

7. Confirm that there are no errors in the OMS Agent log:  
```tail /var/opt/microsoft/omsagent/<workspace id>/log/omsagent.log```

8. The events will appear in OMS under the **CommonSecurityLog** type.  
Log search query: ```Type=CommonSecurityLog```

[1]: https://github.com/Microsoft/OMS-Agent-for-Linux/blob/master/installer/conf/omsagent.d/fortigate_events.conf
