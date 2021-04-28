import copy
import subprocess

from error_codes import *

# backwards compatible input() function for Python 2 vs 3
try:
    input = raw_input
except NameError:
    pass

# error info edited when error occurs
error_info = []

# list of all errors called when script ran
err_summary = []



# set of all errors which are actually warnings
warnings = set([WARN_FILE_PERMS, WARN_LOG_ERRS, WARN_LOG_WARNS, WARN_LARGE_FILES])

# dictionary correlating error codes to error messages
error_messages = {
    ERR_SUDO_PERMS : "Couldn't access {0} due to inadequate permissions. Please run the troubleshooter "\
          "as root in order to allow access.",
    ERR_FOUND : "Please go through the output above to find the errors caught by the troubleshooter.",
    ERR_BITS : "Couldn't get if CPU is 32-bit or 64-bit.",
    ERR_OS_VER : "This version of {0} ({1}) is not supported. Please download {2}. To see all "\
          "supported Operating Systems, please go to:\n"\
          "\n   https://docs.microsoft.com/en-us/azure/azure-monitor/platform/log-analytics-agent#supported-linux-operating-systems\n",
    ERR_OS : "{0} is not a supported Operating System. To see all supported Operating "\
          "Systems, please go to:\n"\
          "\n   https://docs.microsoft.com/en-us/azure/azure-monitor/platform/log-analytics-agent#supported-linux-operating-systems\n",
    ERR_FINDING_OS : "Coudln't determine Operating System. To see all supported Operating "\
          "Systems, please go to:\n"\
          "\n   https://docs.microsoft.com/en-us/azure/azure-monitor/platform/log-analytics-agent#supported-linux-operating-systems\n",
    ERR_FREE_SPACE : "There isn't enough space in directory {0} to install OMS - there needs to be at least 500MB free, "\
          "but {0} has {1}MB free. Please free up some space and try installing again.",
    ERR_PKG_MANAGER : "This system does not have a supported package manager. Please install 'dpkg' or 'rpm' "\
          "and run this troubleshooter again.",
    ERR_OMSCONFIG : "OMSConfig isn't installed correctly.",
    ERR_OMI : "OMI isn't installed correctly.",
    ERR_SCX : "SCX isn't installed correctly.",
    ERR_OMS_INSTALL : "OMS isn't installed correctly.",
    ERR_OLD_OMS_VER : "You are currently running OMS Version {0}. This troubleshooter only "\
          "supports versions 1.11 and newer. Please upgrade to the newest version. You can find "\
          "more information at the link below:\n"\
          "\n    https://docs.microsoft.com/en-us/azure/azure-monitor/platform/log-analytics-agent#installation-and-configuration\n",
    ERR_GETTING_OMS_VER : "Couldn't get most current released version of OMS.",
    ERR_FILE_MISSING : "{0} {1} doesn't exist.",
    WARN_FILE_PERMS : "{0} {1} has {2} {3} instead of {2} {4}.",
    ERR_CERT : "Certificate is invalid, please check {0} for the issue.",
    ERR_RSA_KEY : "RSA key is invalid, please check {0} for the issue.",
    ERR_FILE_EMPTY : "File {0} is empty.",
    ERR_INFO_MISSING : "Couldn't get {0}. Please check {1} for the issue.",
    ERR_ENDPT : "Machine couldn't connect to {0}: openssl command failed. "\
          "Please run the command below for more information on the failure:\n"\
          "\n  $ {1}\n",
    ERR_GUID : "The agent is configured to report to a different workspace - the GUID "\
          "given is {0}, while the workspace is {1}.",
    ERR_OMS_WONT_RUN : "The agent isn't running / will not start. {0}",
    ERR_OMS_STOPPED : "The agent is currently stopped. Run the command below to start it:\n"\
          "\n  $ sudo /opt/microsoft/omsagent/bin/service_control start\n",
    ERR_OMS_DISABLED : "The agent is currently disabled. Run the command below to enable it:\n"\
          "\n  $ sudo /opt/microsoft/bin/service_control enable\n\n"\
          "And run the command below to start it:\n"\
          "\n  $ sudo /opt/microsoft/omsagent/bin/service_control start\n",
    ERR_FILE_ACCESS : "Couldn't access / run {0} due to the following reason: {1}.",
    WARN_LOG_ERRS : "Found errors in log file {0}: {1}",
    WARN_LOG_WARNS : "Found warnings in log file {0}: {1}",
    ERR_HEARTBEAT : "Heartbeats are failing to send data to the workspace.",
    ERR_MULTIHOMING : "Machine registered with more than one log analytics workspace. List of "\
          "workspaces: {0}",
    ERR_INTERNET : "Machine is not connected to the internet: openssl command failed. "\
          "Please run the command below for more information on the failure:\n"\
          "\n  $ {0}\n",
    ERR_QUERIES : "The following queries failed: {0}.",
    ERR_SYSLOG_WKSPC : "Syslog collection is set up for workspace {0}, but OMS is set up with "\
          "workspace {1}. Please see {2} for the issue.",
    ERR_PT : "With protocol type {0}, ports need to be preceded by '{1}', but currently "\
          "are preceded by '{2}'. Please see {3} for the issue.",
    ERR_PORT_MISMATCH : "Syslog is set up to bind to port {0}, but is currently sending to port {1}. "\
          "Please see {2} for the issue.",
    ERR_PORT_SETUP : "Issue with setting up ports for syslog. Please see {0} and {1} for the issue.",
    ERR_SERVICE_CONTROLLER : "Couldn't find 'systemctl' on machine. Please download 'systemctl' and try again.",
    ERR_SYSLOG : "Couldn't find either 'rsyslog' or 'syslogng' on machine. Please download "\
          "one of the two services and try again.",
    ERR_SERVICE_STATUS : "{0} current status is the following: '{1}'. Please check the status of {0} "\
          "using {2} for more information.",
    ERR_CL_FILEPATH : "Custom log pos file {0} contains a different path to the custom log than {1}."\
          "Please see {2} and {0} for more information.",
    ERR_CL_UNIQUENUM : "Custom log {0} has unique number '0x{1}', but pos file {2} has unique number "\
          "'0x{3}'. Please see {4} and {2} for more information.",
    ERR_OMICPU : "Ran into the following error when trying to see if OMI has high CPU: \n  {0}",
    ERR_OMICPU_HOT : "OMI appears to be running itself at >80% CPU. Please check out {0} for more information.",
    ERR_OMICPU_NSSPEM : "Your version of nss-pem is slightly out of date, causing OMI to run at 100% CPU. "\
          "Please run the below command to upgrade the nss-pem package:\n"\
          "\n  $ sudo yum upgrade upgrade nss-pem\n\n"\
          "If nss-pem is not available for upgrade, then please instead downgrade curl using this command:\n"\
          "\n  $ sudo yum downgrade curl libcurl\n\n"\
          "After either option, please restart OMI using this command:\n"\
          "\n  $ sudo scxadmin -restart\n\n"\
          "You can read more about how to fix this specific bug by going to:\n"\
          "\n    https://docs.microsoft.com/en-us/azure/azure-monitor/platform/agent-linux-troubleshoot#issue-you-see-omiagent-using-100-cpu",
    ERR_OMICPU_NSSPEM_LIKE : "There seems to be an issue similar to a common issue involving OMI agent using "\
          "100% CPU. Please check the below link for more information:\n"\
          "\n    https://docs.microsoft.com/en-us/azure/azure-monitor/platform/agent-linux-troubleshoot#issue-you-see-omiagent-using-100-cpu",
    ERR_SLAB : "Ran into the following error when trying to run slabtop: \n  {0}",
    ERR_SLAB_BLOATED : "Your machine has an issue with the dentry cache becoming bloated. Please check the "\
          "top 10 caches below, sorted by cache size:\n{0}",
    ERR_SLAB_NSSSOFTOKN : "Your version of nss-softokn is slightly out of date, causing an issue with "\
          "bloating the dentry cache. Please upgrade your version to nss-softokn-3.14.3-12.el6 "\
          "or newer, and ensure that the NSS_SDB_USE_CACHE environment variable is set to 'yes'. "\
          "Please check the below link for more information:\n"\
          "\n    https://bugzilla.redhat.com/show_bug.cgi?format=multiple&id=1044666",
    ERR_SLAB_NSS : "There appears to be an issue in NSS, which resulted in bloating the dentry cache. "\
          "Please set the NSS_SDB_USE_CACHE environment variable to 'yes'. You can check the "\
          "below link for more information:\n"\
          "\n    https://docs.microsoft.com/en-us/azure/azure-monitor/platform/agent-linux-troubleshoot#issue-you-see-omiagent-using-100-cpu",
    ERR_LOGROTATE_SIZE : "Logrotate size limit for log {0} has invalid formatting. Please see {1} for more "\
          "information.",
    ERR_LOGROTATE : "Logrotate isn't rotating log {0}: its current size is {1}, and it should have "\
          "been rotated at {2}. Please see {3} for more information.",
    WARN_LARGE_FILES : "File {0} has been modified {1} times in the last {2} seconds.",
    ERR_PKG : "{0} isn't installed correctly.",
    ERR_BACKEND_CONFIG : "The agent is currently having issues with pulling the configuration from the backend. "\
          "You can try manually pulling the config by running the below command:\n"\
          "\n  $ sudo su omsagent -c 'python /opt/microsoft/omsconfig/Scripts/PerformRequiredConfigurationChecks.py'\n\n"\
          "Please check the following log files for more information:\n"\
          "    {0}\n"\
          "    {1}\n"\
          "Please also check out the below link for more information:\n"\
          "\n    https://docs.microsoft.com/en-us/azure/azure-monitor/platform/agent-linux-troubleshoot#issue-you-are-not-seeing-any-custom-log-data",
    ERR_PYTHON_PKG : "This version of Python is missing the {0} package. (You can check by opening up "\
          "python and typing 'import {0}'.) Please install this package and run the troubleshooter again."

}



# check if either has no error or is warning
def is_error(err_code):
    not_errs = warnings.copy()
    not_errs.add(NO_ERROR)
    return (err_code not in not_errs)



# for getting inputs from the user
def get_input(question, check_ans, no_fit):
    answer = input(" {0}: ".format(question))
    while (not check_ans(answer.lower())):
        print("Unclear input. {0}".format(no_fit))
        answer = input(" {0}: ".format(question))
    return answer



# ask user if they want to reinstall OMS Agent
def ask_reinstall():
    answer = get_input("Would you like to uninstall and reinstall OMS Agent? (y/n)",\
                       (lambda x : x.lower() in ['y','yes','n','no']),\
                       "Please type either 'y'/'yes' or 'n'/'no' to proceed.")
    if (answer.lower() in ['y','yes']):
        print("Please run the command:")
        print("\n    sudo sh ./omsagent-*.universal.x64.sh --purge\n")
        print("to uninstall, and then run the command:")
        print("\n    sudo sh ./omsagent-*.universal.x64.sh --install\n")
        print("to reinstall.")
        return USER_EXIT

    elif (answer.lower() in ['n','no']):
        print("Continuing on with troubleshooter...")
        print("--------------------------------------------------------------------------------")
        return ERR_FOUND

def ask_restart_oms():
    answer = get_input("Would you like to restart OMS Agent? (y/n)",\
                       (lambda x : x.lower() in ['y','yes','n','no']),\
                       "Please type either 'y'/'yes' or 'n'/'no' to proceed.")

    if (answer.lower() in ['y','yes']):
        print("Restarting OMS Agent...")
        sc_path = '/opt/microsoft/omsagent/bin/service_control'
        try:
            subprocess.check_output([sc_path, 'restart'], universal_newlines=True,\
                                    stderr=subprocess.STDOUT)
            return NO_ERROR
        except subprocess.CalledProcessError:
            error_info.append(('executable shell script', sc_path))
            return ERR_FILE_MISSING

    elif (answer.lower() in ['n','no']):
        print("Continuing on with troubleshooter...")
        print("--------------------------------------------------------------------------------")
        return ERR_FOUND

def ask_continue():
    answer = get_input("Would you like to continue with the troubleshooter? (y/n)",\
                       (lambda x : x.lower() in ['y','yes','n','no']),\
                       "Please type either 'y'/'yes' or 'n'/'no' to proceed.")
    if (answer.lower() in ['y','yes']):
        print("Continuing on with troubleshooter...")
        print("--------------------------------------------------------------------------------")
        return ERR_FOUND
    elif (answer.lower() in ['n','no']):
        print("Exiting troubleshooter...")
        print("================================================================================")
        return USER_EXIT



def print_errors(err_code):
    not_errors = set([NO_ERROR, USER_EXIT])
    if (err_code in not_errors):
        return err_code

    warning = False
    if (err_code in warnings):
        warning = True

    err_string = error_messages[err_code]

    # no formatting
    if (error_info == []):
        err_string = "ERROR FOUND: {0}".format(err_string)
        err_summary.append(err_string)
        print(err_string)
    # needs input
    else:
        while (len(error_info) > 0):
            tup = error_info.pop(0)
            temp_err_string = err_string.format(*tup)
            if (warning):
                final_err_string = "WARNING FOUND: {0}".format(temp_err_string)
            else:
                final_err_string = "ERROR FOUND: {0}".format(temp_err_string)
            err_summary.append(final_err_string)

    if (warning):
        print("WARNING(S) FOUND.")
        return NO_ERROR
    else:
        print("ERROR(S) FOUND.")
        return ERR_FOUND