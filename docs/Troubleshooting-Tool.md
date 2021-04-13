# Troubleshooting Tool for OMS Agent for Linux
The following document provides quick information on how to install the Troubleshooting Tool, as well as some common error codes.

# Table of Contents
- [Troubleshooter Basics](#troubleshooter-basics)
- [Installing the Troubleshooter](#installing-the-troubleshooter)
- [Requirements](#requirements)
- [Scenarios Covered](#scenarios-covered)
- [List of Possible Errors](#list-of-possible-errors)

## Troubleshooter Basics

The OMS Linux Troubleshooter is designed in order to help find and diagnose issues with the agent, as well as general health checks. 

## Installing the Troubleshooter

The OMS Troubleshooter is automatically installed upon installation of the OMS Agent. However, if installation fails in any way, it can also be installed manually by following the steps below.

### Manual Install of the Troubleshooter
1. Copy the troubleshooter bundle onto your machine: `wget https://raw.github.com/microsoft/OMS-Agent-for-Linux/master/source/code/troubleshooter/omsagent_tst.tar.gz`
2. Unpack the bundle: `tar -xzvf omsagent_tst.tar.gz`
3. Run the manual installation: `sudo ./install_tst`

If it installed successfully, the troubleshooter can be run using `sudo /opt/microsoft/omsagent/bin/troubleshooter`

## Requirements

The OMS Troubleshooter requires Python 2.6+ installed on the machine, but will work with either Python2 or Python3. In addition, gdb is required to run, as well as the following Python packages:
| Python Package | Required for Python2? | Required for Python3? |
| --- | --- | --- |
| copy | **yes** | **yes** |
| errno | **yes** | **yes** |
| os | **yes** | **yes** |
| platform | **yes** | **yes** |
| re | **yes** | **yes** |
| socket | **yes** | **yes** |
| ssl | **yes** | **yes** |
| subprocess | **yes** | **yes** |
| urllib2 | **yes** | no |
| urllib.request | no | **yes** |

## Scenarios Covered

1. Agent is unhealthy, heartbeat doesn't work properly
	* Verify agent is installed / connected
	* Check if running multi-homing (multi-homing is not supported yet)
	* Verify OMSAgent is currently running
	* Start / restart OMSAgent if necessary
	* Check if OMSAgent is encountering an error in omsagent.log
2. Agent doesn't start, can't connect to Log Analytic Services
	* Ask about error codes encountered during onboarding
	* Verify agent is installed
	* Check omsadmin.conf
	* Check internet connectivity
	* Check agent service endpoint connectivity
	* Check log analytics endpoints connectivity
	* Run queries to see if logs are flowing
3. Agent syslog isn't working
	* Verify agent is installed / connected / healthy
	* Check if machine is running rsyslog or syslog-ng
	* Check 95-omsagent.conf for configuration errors
	* Check syslog.conf for configuration errors
	* Verify data is being sent to port
4. Agent has high CPU / memory usage
	* Verify agent is installed / connected / healthy
	* Check if logs are rotating correctly with logrotate
	* Check if OMI is running at 100% CPU
	* Check if slab memory / dentry cache usage is erroring
5. Agent having installation issues
	* Ask about error codes encountered during installation
	* Check OS version is supported
	* Check disk space
	* Check package manager
	* Check package installation (DSC, OMI, SCX)
	* Check OMS version
	* Check location / permissions on files
	* Check certificate and RSA key
6. Agent custom logs aren't working
	* Ask user if running custom logs
	* Verify agent is installed / connected / healthy
	* Check if agent has pulled configuration from OMS backend
	* Check customlog.conf for configuration errors
	* Parse through custom logs for errors
7. (A) Run all scenarios
	* Run through scenarios 1-6 in the following order: 5, 2, 1, 4, 3, 6
8. (L) Collect logs
	* Run OMS Agent Log Collector
9. No issues found
	* Tell customer what information to collect

## List of Possible Errors

Below is a list of the errors that can be caught by the troubleshooter:

| Error | Error Code | Meaning |
| --- | --- | --- |
| NO_ERROR | 0 | No errors found |
| USER_EXIT | 1 | User requested to exit |
| ERR_SUDO_PERMS | 100 | Not running as root |
| ERR_FOUND | 101 | Errors found earlier |
| ERR_BITS | 102 | Couldn't get 32-bit vs 64-bit |
| ERR_OS_VER | 103 | Supported OS, but wrong version |
| ERR_OS | 104 | Unsupported OS |
| ERR_FINDING_OS | 105 | Couldn't figure out OS |
| ERR_FREE_SPACE | 106 | Not enough space on VM |
| ERR_PKG_MANAGER | 107 | No supported package manager (dpkg or rpm) |
| ERR_OMSCONFIG | 108 | OMSConfig not installed correctly |
| ERR_OMI | 109 | OMI not installed correctly |
| ERR_SCX | 110 | SCX not installed correctly |
| ERR_OMS_INSTALL | 111 | OMS not installed correctly |
| ERR_OLD_OMS_VER | 112 | OMS version is too old for troubleshooter (< 1.11) |
| ERR_GETTING_OMS_VER | 113 | Couldn't get most current OMS version |
| ERR_FILE_MISSING | 114 | Missing directory / file / link |
| WARN_FILE_PERMS | 115 | Wrong permissions for directory / file / link |
| ERR_CERT | 116 | Invalid certificate |
| ERR_RSA_KEY | 117 | Invalid RSA key |
| ERR_FILE_EMPTY | 118 | File empty |
| ERR_INFO_MISSING | 119 | File missing some information |
| ERR_ENDPT | 120 | Endpoint couldn't connect |
| ERR_GUID | 121 | GUID different from WSID |
| ERR_OMS_WONT_RUN | 122 | OMSAgent not running |
| ERR_OMS_STOPPED | 123 | OMSAgent stopped |
| ERR_OMS_DISABLED | 124 | OMSAgent disabled |
| ERR_FILE_ACCESS | 125 | Couldn't access file |
| WARN_LOG_ERRS | 126 | Error in logs |
| WARN_LOG_WARNS | 127 | Warning in logs |
| ERR_HEARTBEAT | 128 | Heartbeats failing to send data to workspace |
| ERR_MULTIHOMING | 129 | Running multihoming |
| ERR_INTERNET | 130 | Couldn't connect to internet |
| ERR_QUERIES | 131 | Queries failed |
| ERR_SYSLOG_WKSPC | 132 | Syslog collecting to wrong workspace |
| ERR_PT | 133 | Wrong number of '@'s in omsagent95 paths |
| ERR_PORT_MISMATCH | 134 | Ports don't match up |
| ERR_PORT_SETUP | 135 | Error with ports |
| ERR_SERVICE_CONTROLLER | 136 | No systemctl on machine |
| ERR_SYSLOG | 137 | No rsyslog or syslog-ng on machine |
| ERR_SERVICE_STATUS | 138 | Service erroring |
| ERR_CL_FILEPATH | 139 | Custom log filepath mismatch |
| ERR_CL_UNIQUENUM | 140 | Unique number mismatch |
| ERR_OMICPU | 141 | OMI high CPU script ran into error |
| ERR_OMICPU_HOT | 142 | OMI high CPU script shows OMI running too hot |
| ERR_OMICPU_NSSPEM | 143 | OMI 100% CPU bug, upgrade nss-pem to fix |
| ERR_OMICPU_NSSPEM_LIKE | 144 | Similar to OMI 100% CPU bug |
| ERR_SLAB | 145 | Slabtop issue in checking slab memory |
| ERR_SLAB_BLOATED | 146 | Slab memory has >300 DNE messages, no dentry |
| ERR_SLAB_NSSSOFTOKN | 147 | Dentry cache issue, upgrade nss-softokn to fix |
| ERR_SLAB_NSS | 148 | Dentry cache issue, initialize NSS variable to fix |
| ERR_LOGROTATE_SIZE | 149 | Logrotate has wrong size formatting |
| ERR_LOGROTATE | 150 | Logrotate isn't rotating logs |
| WARN_LARGE_FILES | 151 | Large files growing in size |
| ERR_PKG | 152 | Couldn't find package |
| ERR_BACKEND_CONFIG | 153 | Can't pull config from backend |
| ERR_PYTHON_PKG | 154 | Missing Python package |
