# INSPIRED BY update_mgmt_health_check.py

import os
import subprocess

from error_codes import *
from errors      import error_info
from helpers     import geninfo_lookup

OMSADMIN_PATH = "/etc/opt/microsoft/omsagent/conf/omsadmin.conf"
CERT_PATH = "/etc/opt/microsoft/omsagent/certs/oms.crt"
KEY_PATH = "/etc/opt/microsoft/omsagent/certs/oms.key"
SSL_CMD = "echo | openssl s_client -connect {0}:443 -brief"



# openssl connect to specific endpoint
def check_endpt_ssl(ssl_cmd, endpoint):
    try:
        ssl_output = subprocess.check_output(ssl_cmd.format(endpoint), shell=True,\
                     stderr=subprocess.STDOUT, universal_newlines=True)
        ssl_output_lines = ssl_output.split('\n')
        
        (connected, verified) = (False, False)
        for line in ssl_output_lines:
            if (line == "CONNECTION ESTABLISHED"):
                connected = True
                continue
            if (line == "Verification: OK"):
                verified = True
                continue

        if (connected and verified):
            return True
        else:
            return False
    except Exception:
        return False



# check general internet connectivity
def check_internet_connect():
    if (check_endpt_ssl(SSL_CMD, "docs.microsoft.com")):
        return NO_ERROR
    else:
        error_info.append((SSL_CMD.format("docs.microsoft.com"),))
        return ERR_INTERNET



# check agent service endpoint
def check_agent_service_endpt():
    ssl_command = SSL_CMD

    # get endpoint
    dsc_endpt = geninfo_lookup('DSC_ENDPOINT')
    if (dsc_endpt == None):
        error_info.append(('DSC (agent service) endpoint', OMSADMIN_PATH))
        return ERR_INFO_MISSING
    agent_endpt = dsc_endpt.split('/')[2]

    # check without certs
    if (check_endpt_ssl(ssl_command, agent_endpt)):
        return NO_ERROR
    else:
        # try with certs (if they exist)
        if (os.path.isfile(CERT_PATH) and os.path.isfile(KEY_PATH)):
            ssl_command = "{0} -cert {1} -key {2}".format(SSL_CMD, CERT_PATH, KEY_PATH)
            if (check_endpt_ssl(ssl_command, agent_endpt)):
                return NO_ERROR
        else:
            # lets user know cert and key aren't there
            print("NOTE: Certificate and key files don't exist, OMS isn't onboarded.")

        error_info.append((agent_endpt, ssl_command.format(agent_endpt)))
        return ERR_ENDPT




# check log analytics endpoints
def check_log_analytics_endpts():
    success = NO_ERROR
    no_certs_printed = False

    # get OMS endpoint to check if fairfax region
    oms_endpt = geninfo_lookup('OMS_ENDPOINT')
    if (oms_endpt == None):
        error_info.append(('OMS endpoint', OMSADMIN_PATH))
        return ERR_INFO_MISSING

    # get workspace ID
    workspace_id = geninfo_lookup('WORKSPACE_ID')
    if (workspace_id == None):
        error_info.append(('Workspace ID', OMSADMIN_PATH))
        return ERR_INFO_MISSING

    # get log analytics endpoints
    if ('.us' in oms_endpt):
        log_analytics_endpts = ["usge-jobruntimedata-prod-1.usgovtrafficmanager.net", \
            "usge-agentservice-prod-1.usgovtrafficmanager.net", "*.ods.opinsights.azure.us", \
            "*.oms.opinsights.azure.us"]
    else:
        log_analytics_endpts = ["*.ods.opinsights.azure.com", "*.oms.opinsights.azure.com", \
            "ods.systemcenteradvisor.com"]

    for endpt in log_analytics_endpts:
        ssl_command = SSL_CMD

        # replace '*' with workspace ID
        if ('*' in endpt):
            endpt = endpt.replace('*', workspace_id)

        # check endpoint without certs
        if (not check_endpt_ssl(ssl_command, endpt)):
            # try with certs (if they exist)
            if (os.path.isfile(CERT_PATH) and os.path.isfile(KEY_PATH)):
                ssl_command = "{0} -cert {1} -key {2}".format(SSL_CMD, CERT_PATH, KEY_PATH)
                if (not check_endpt_ssl(ssl_command, endpt)):
                    error_info.append((endpt, ssl_command.format(endpt)))
                    success = ERR_ENDPT
            else:
                # lets user know cert and key aren't there
                if (not no_certs_printed):
                    print("NOTE: Certificate and key files don't exist, OMS isn't onboarded.")
                    no_certs_printed = True

                error_info.append((endpt, ssl_command.format(endpt)))
                success = ERR_ENDPT

    return success