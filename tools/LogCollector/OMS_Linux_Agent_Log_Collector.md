# OMS Linux Agent Log Collector

## [Supported Linux OS](https://github.com/Microsoft/OMS-Agent-for-Linux/tree/master#supported-linux-operating-systems)

## Log Collector Pre-requisites:
Make sure the target Linux server has the following software installed:
- Python 2.6 and above
- OMS Linux Agent (From GitHub / Azure VM Extension / Linux Containers)

You can use OMS Log collector to collect logs for both failed and successful installations of the OMS Linux Agent

## Log Collector Download:
- Download the tool and copy to any directory of your choice:
    ```
    wget https://github.com/Microsoft/OMS-Agent-for-Linux/raw/master/tools/LogCollector/download/v6/omslinux_agentlog.tgz
    ```
    Recommendation is to copy the tool to the user’s home directory (/home/user)
- Untar the archive file to extract OMS Log Collector source files:
    ```
    tar -xvf omslinux_agentlog.tgz
    ```

You are ready to run the tool now to collect logs

## Log Collector Execution Syntax:
```
cd <directory in which you extracted omslinux_agentlog.tgz>
sudo sh omslinux_agentlog.sh [-h] -s <SR Number> [-c <Company Name>]
```
Examples:
```
sudo sh omslinux_agentlog.sh -s SR1234567890 -c Contoso
# or
sudo sh omslinux_agentlog.sh -s SR1234567890
```

**Note:**
The tool can optionally be run directly using the python script (you may need to use `python2` or `python3` if your python command is unaliased):
```
sudo python omslinux_agentlog.py [-h] -s <SR Number> [-c <Company Name>]
```
Examples:
```
sudo python omslinux_agentlog.py -s SR1234567890 -c Contoso
# or
sudo python omslinux_agentlog.py -s SR1234567890
```

## Log Collector Source File Manifest:
- `omslinux_agentlog.sh`: A shell script to check pre-requisites are installed and call the python script to start collecting logs and command outputs
- `omslinux_agentlog.py`: A python script to collect LOGS and COMMAND Line output for further troubleshooting

## Log Collector Output Files and Directories:
- All logs are saved under `/tmp/omslogs/`
- The tool output is archived under below file name format under `/tmp/`:
    omslinuxagentlog-\<SR Number\>-\<UTCDateTime\>.tgz
    Example: `omslinuxagentlog-SR1234567890-2017-06-14T11:57:01.599947.tgz`
- Copy the above file and send it to MS Support for further troubleshooting

### Files / Directories Contained:
* OMS Linux Agent Type:
    * Installed using omsagent*.universal*.sh bundle direcly
        * /tmp/omslogs/
            * messages
            * omsagent.log
            * omsconfig.log
            * omslinux.out
            * scx*.log
            * omi*.log
            * WSData/
    * Addtional logs if it is installed through Azure VM extension
        * /tmp/omslogs/
            * extension/
            * vmagent/
            * messages
            * omsagent.log
            * omsconfig.log
            * omslinux.out
        * /tmp/omslogs/extension/
            * config/
            * status/
            * lib/
            * log/
        * /tmp/omslogs/vmagent/
            * waagent.log
    * Linux Containers
        * /tmp/omslogs/
            * container/
            * omslinux.out
        * /tmp/omslogs/container/
            * omsagent.log
            * omsconfig.log
            * syslog

## References:
- [Connect your Linux Computers to Operations Management Suite (OMS)](https://docs.microsoft.com/en-us/azure/log-analytics/log-analytics-agent-linux)
- [Troubleshooting Guide for OMS Agent for Linux (including error codes)](https://docs.microsoft.com/en-us/azure/azure-monitor/platform/agent-linux-troubleshoot)
- [OMS Agent for Linux Azure VM extension documentation](https://docs.microsoft.com/en-us/azure/virtual-machines/linux/extensions-oms)
- [Connect Azure virtual machines to Log Analytics with a Log Analytics agent](https://docs.microsoft.com/en-us/azure/log-analytics/log-analytics-azure-vm-extension)

## APPENDIX:
### How to publish new version of Log collector
- After your code review is merged, create a tgz file by navigating to `/home/your_working_directory/OMS-Agent-for-Linux/tools/LogCollector/source` and run:
   ```
   tar -cvzf omslinux_agentlog.tgz ./*
   ```  
- Create a new folder with the version number under download folder. Example `https://github.com/Microsoft/OMS-Agent-for-Linux/tree/master/tools/LogCollector/download/v2`
- Update documentation with the new changes: `https://github.com/Microsoft/OMS-Agent-for-Linux/blob/master/tools/LogCollector/OMS_Linux_Agent_Log_Collector.md`
- Publish new version of omslinux_agent.tgz to download folder.
### Sample output for GitHub OMS Linux Agent:

![ExampleLogCollectorScriptOutputGitHub](pictures/ExampleLogCollectorScriptOutputGitHub.png?raw=true)
 
### Sample output for OmsAgentForLinux Azure VM Extension:
 
![ExampleLogCollectorScriptOutputExtension](pictures/ExampleLogCollectorScriptOutputExtension.png?raw=true)

### Sample output for OMS Linux Container:
 
![ExampleLogCollectorScriptOutputContainer](pictures/ExampleLogCollectorScriptOutputContainer.png?raw=true)
