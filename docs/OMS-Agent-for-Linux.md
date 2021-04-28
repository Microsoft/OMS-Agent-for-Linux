# Contents

- [Getting Started](getting-started)
  - [The Log Analytics agent for Linux](#the-log-analytics-agent-for-linux)
	- [Package Requirements](#package-requirements)
	- [Upgrade from a Previous Release](#upgrade-from-a-previous-release)
	- [Steps to install the Log Analytics agent for Linux](#steps-to-install-the-log-analytics-agent-for-linux)
	- [Configuring the agent for use with an HTTP proxy server](#configuring-the-agent-for-use-with-an-http-proxy-server)
- [Onboarding with Log Analytics](#onboarding-with-log-analytics)
  - [Onboarding using the command line](#onboarding-using-the-command-line)
  - [Onboarding using a file](#onboarding-using-a-file)	

# Getting Started

## The Log Analytics agent for Linux
The Log Analytics agent for Linux comprises multiple packages. The release file contains the following packages, available by running the shell bundle with `--extract`:

**Package** | **Version** | **Description**
----------- | ----------- | --------------
omsagent | 1.13.35 | The Operations Management Suite Agent for Linux
omsconfig | 1.1.1 | Configuration agent for the OMS Agent
omi | 1.6.4 | Open Management Infrastructure (OMI) -- a lightweight CIM Server. *Note that OMI requires root access to run a cron job necessary for the functioning of the service*
scx | 1.6.4 | OMI CIM Providers for operating system performance metrics
apache-cimprov | 1.0.1 | Apache HTTP Server performance monitoring provider for OMI. Only installed if Apache HTTP Server is detected.
mysql-cimprov | 1.0.1 | MySQL Server performance monitoring provider for OMI. Only installed if MySQL/MariaDB server is detected.
docker-cimprov | 1.0.0 | Docker provider for OMI. Only installed if Docker is detected.

**Additional Installation Artifacts**
After installing the Log Analytics agent for Linux packages, the following additional system-wide configuration changes are applied. These artifacts are removed when the omsagent package is uninstalled.
* A non-privileged user named: `omsagent` is created. This is the account the omsagent daemon runs as
* A sudoers “include” file is created at /etc/sudoers.d/omsagent This authorizes omsagent to restart the syslog and omsagent daemons. If sudo “include” directives are not supported in the installed version of sudo, these entries will be written to /etc/sudoers.
* The syslog configuration is modified to forward a subset of events to the agent. For more information, see the **Configuring Data Collection** section below


## Package Requirements
 **Required package** | **Description** | **Minimum version**
--------------------- | --------------------- | -------------------
Glibc |	GNU C Library	| 2.5-12 
Openssl	| OpenSSL Libraries | 1.0.1 or 1.1.x
Curl | cURL web client | 7.15.5
Python 2 | | 2.6
Python-ctypes | |
PAM | Pluggable Authentication Modules |

**Note**: Either rsyslog or syslog-ng are required to collect syslog messages. The default syslog daemon on version 5 of Red Hat Enterprise Linux, CentOS, and Oracle Linux version (sysklog) is not supported for syslog event collection. To collect syslog data from this version of these distributions, the rsyslog daemon should be installed and configured to replace sysklog.

Please also review the [list of supported distros and versions.](https://docs.microsoft.com/azure/azure-monitor/platform/log-analytics-agent#supported-linux-operating-systems)

## Upgrade from a Previous Release
Upgrade from prior versions (>1.0.0-47) is supported in this release. Performing the installation with the --upgrade command will upgrade all components of the agent to the latest version.


### Steps to install the Log Analytics agent for Linux
The Log Analytics agent for Linux is provided in a self-extracting and installable shell script bundle. This bundle contains Debian and RPM packages for each of the agent components and can be installed directly or extracted to retrieve the individual packages. One bundle is provided for x64 architectures and one for x86 architectures. 

You can install agents on your Azure VMs using the [Azure Log Analytics VM extension](https://docs.microsoft.com/azure/virtual-machines/extensions/oms-linux?toc=%2Fazure%2Fazure-monitor%2Ftoc.json) for Linux, and for machines in a hybrid environment using the shell script bundle. 

**Installing the agent**

1. Transfer the appropriate bundle (x86 or x64) to your Linux computer, using scp/sftp.
2. Install the bundle by using the `--install` or `--upgrade` argument. Note: You need to use the `--upgrade` argument if any dependent packages such as omi, scx, omsconfig or their older versions are installed, as would be the case if the system Center Operations Manager agent for Linux is already installed. To onboard to an Azure Monitor Log Analytics workspace during installation, provide the `-w <WorkspaceID>` and `-s <workspaceKey>` parameters.


**To install and onboard directly:**
```
sudo sh ./omsagent-*.universal.x64.sh --upgrade -w <workspace id> -s <shared key>
```

**To install and onboard directly using an HTTP proxy:**
```
sudo sh ./omsagent-*.universal.x64.sh --upgrade -p http://<proxy user>:<proxy password>@<proxy address>:<proxy port> -w <workspace id> -s <shared key>
```

**To install and onboard to a workspace in FairFax:**
```
sudo sh ./omsagent-*.universal.x64.sh --upgrade -w <workspace id> -s <shared key> -d opinsights.azure.us
```

**To install the agent packages and onboard at a later time:**
```
sudo sh ./omsagent-*.universal.x64.sh --upgrade
```

**To extract the agent packages from the bundle without installing:**
```
sudo sh ./omsagent-*.universal.x64.sh --extract
```

**All bundle operations:**
```
Options:
  --extract              Extract contents and exit.
  --force                Force upgrade (override version checks).
  --install              Install the package from the system.
  --purge                Uninstall the package and remove all related data.
  --restart-deps         Reconfigure and restart dependent service
  --source-references    Show source code reference hashes.
  --upgrade              Upgrade the package in the system.
  --version              Version of this shell bundle.
  --version-check        Check versions already installed to see if upgradable.
  --debug                use shell debug mode.
  
  -w id, --id id         Use workspace ID <id> for automatic onboarding.
  -s key, --shared key   Use <key> as the shared key for automatic onboarding.
  -d dmn, --domain dmn   Use <dmn> as the OMS domain for onboarding. Optional.
                         default: opinsights.azure.com
                         ex: opinsights.azure.us (for FairFax)
  -p conf, --proxy conf  Use <conf> as the proxy configuration.
                         ex: -p [protocol://][user:password@]proxyhost[:port]
  -a id, --azure-resource id Use Azure Resource ID <id>.

  -? | --help            shows this usage text.
```

## Configuring the agent for use with an HTTP proxy server
Communication between the agent and Log Analytics service can use an HTTP or HTTPS proxy server. Both anonymous and basic authentication (username/password) proxies are supported. 

**Proxy Configuration**
The proxy configuration value has the following syntax:
[protocol://][user:password@]proxyhost[:port]

Property|Description
-|-
Protocol|http or https
user|(optional) username for proxy authentication
password|(optional) password for proxy authentication
proxyhost|Address or FQDN of the proxy server
port|Optional port number for the proxy server

For example:
http://user01:password@proxy01.contoso.com:8080

The Log Analytics agent only creates secure connection over http. Even if you specify the protocol as http, please note that http requests are created using SSL/TLS secure connection so the proxy must support SSL/TLS. The proxy server can be specified during installation or directly in a file (at any point). 

**Specify proxy configuration during installation:**
The `-p` or `--proxy` argument to the omsagent installation bundle specifies the proxy configuration to use. 

```
sudo sh ./omsagent-*.universal.x64.sh --upgrade -p http://<proxy user>:<proxy password>@<proxy address>:<proxy port> -w <workspace id> -s <shared key>
```
Or using the onboarding script
```
sudo sh ./onboard_agent.sh -p http://<proxy user>:<proxy password>@<proxy address>:<proxy port> -w <workspace id> -s <shared key>
```

**Define the proxy configuration in a file**
The proxy configuration is set in this file: `/etc/opt/microsoft/omsagent/proxy.conf` This file can be directly created or edited, but must be readable by the omsagent user. This file must be updated, and the omsagent daemon restarted, should the proxy configuration change. For example:
```
proxyconf="https://proxyuser:proxypassword@proxyserver01:8080"
sudo echo $proxyconf >>/etc/opt/microsoft/omsagent/proxy.conf
sudo chown omsagent:omiusers /etc/opt/microsoft/omsagent/proxy.conf
sudo chmod 600 /etc/opt/microsoft/omsagent/proxy.conf
sudo /opt/microsoft/omsagent/bin/service_control restart
```

**Removing the proxy configuration**
To remove a previously defined proxy configuration and revert to direct connectivity, remove the proxy.conf file:
```
sudo rm /etc/opt/microsoft/omsagent/proxy.conf
sudo /opt/microsoft/omsagent/bin/service_control restart
```

# Onboarding with Azure Monitor Log Analytics workspace
If a workspace ID and key were not provided during the bundle installation, the agent must be subsequently registered with an Azure Monitor Log Analytics workspace.

## Onboarding using the command line
Run the omsadmin.sh command supplying the workspace id and key for your workspace. This command must be run as root (w/ sudo elevation):
```
cd /opt/microsoft/omsagent/bin
sudo ./omsadmin.sh -w <WorkspaceID> -s <Shared Key>
```

## Onboarding using a file
1.	Create the file `/etc/omsagent-onboard.conf` The file must be readable and writable for root.

`sudo vi /etc/omsagent-onboard.conf`

2.	Insert the following lines in the file with your Workspace ID and Shared Key:

```
WORKSPACE_ID=<WorkspaceID>
SHARED_KEY=<Shared Key>
```

3.	Onboard to an Azure Monitor Log Analytics workspace:

`sudo /opt/microsoft/omsagent/bin/omsadmin.sh`

4.	The file will be deleted on successful onboarding.
