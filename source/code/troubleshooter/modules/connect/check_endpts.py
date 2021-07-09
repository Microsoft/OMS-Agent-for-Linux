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

        return (connected, verified)
    except Exception:
        return (False, False)



# check general internet connectivity
def check_internet_connect():
    (connected_docs, verified_docs) = check_endpt_ssl(SSL_CMD, "docs.microsoft.com")
    if (connected_docs and verified_docs):
        return NO_ERROR
    elif (connected_docs and not verified_docs):
        error_info.append((SSL_CMD.format("docs.microsoft.com"),))
        return WARN_INTERNET
    else:
        error_info.append((SSL_CMD.format("docs.microsoft.com"),))
        return WARN_INTERNET_CONN



# check agent service endpoint
def check_agent_service_endpt():
    # get endpoint
    dsc_endpt = geninfo_lookup('DSC_ENDPOINT')
    if (dsc_endpt == None):
        error_info.append(('DSC (agent service) endpoint', OMSADMIN_PATH))
        return ERR_INFO_MISSING
    agent_endpt = dsc_endpt.split('/')[2]

    # check without certs
    (dsc_connected, dsc_verified) = check_endpt_ssl(SSL_CMD, agent_endpt)
    if (dsc_connected and dsc_verified):
        return NO_ERROR

    else:
        # try with certs (if they exist)
        if (os.path.isfile(CERT_PATH) and os.path.isfile(KEY_PATH)):
            ssl_command = "{0} -cert {1} -key {2}".format(SSL_CMD, CERT_PATH, KEY_PATH)
            (dsc_cert_connected, dsc_cert_verified) = check_endpt_ssl(ssl_command, agent_endpt)
            # with certs connected and verified
            if (dsc_cert_connected and dsc_cert_verified):
                return NO_ERROR
            # with certs connected, but didn't verify
            elif (dsc_cert_connected and not dsc_cert_verified):
                error_info.append((agent_endpt, ssl_command.format(agent_endpt)))
                return WARN_ENDPT
        else:
            # lets user know cert and key aren't there
            print("NOTE: Certificate and key files don't exist, OMS isn't onboarded.")

        # if certs didn't work at all, check to see if no certs was connected (but not verified)
        if (dsc_connected and not dsc_verified):
            error_info.append((agent_endpt, SSL_CMD.format(agent_endpt)))
            return WARN_ENDPT

        # neither with nor without certs connected
        error_info.append((agent_endpt, SSL_CMD.format(agent_endpt)))
        return ERR_ENDPT




# check log analytics endpoints
def check_log_analytics_endpts():
    success = NO_ERROR
    no_certs_printed = False
    connected_err = []
    verified_err = []

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
        # replace '*' with workspace ID
        if ('*' in endpt):
            endpt = endpt.replace('*', workspace_id)

        # check endpoint without certs
        (la_connected, la_verified) = check_endpt_ssl(SSL_CMD, endpt)
        if (not (la_connected or la_verified)):
            # try with certs (if they exist)
            if (os.path.isfile(CERT_PATH) and os.path.isfile(KEY_PATH)):
                ssl_command = "{0} -cert {1} -key {2}".format(SSL_CMD, CERT_PATH, KEY_PATH)
                (la_cert_connected, la_cert_verified) = check_endpt_ssl(ssl_command, endpt)

                # didn't connect or verify with certs
                if (not (la_cert_connected or la_cert_verified)):
                    connected_err.append((endpt, ssl_command.format(endpt)))
                    success = ERR_ENDPT

                # connected but didn't verify with certs
                elif (la_cert_connected and not la_cert_verified):
                    # haven't run into a connected error already
                    if (success != ERR_ENDPT):
                        verified_err.append((endpt, ssl_command.format(endpt)))
                        success = WARN_ENDPT

            else:
                # lets user know cert and key aren't there
                if (not no_certs_printed):
                    print("NOTE: Certificate and key files don't exist, OMS isn't onboarded.")
                    no_certs_printed = True

                # if certs didn't work at all, check to see if no certs was connected (but not verified)
                if (la_connected and not la_verified):
                    # haven't run into a connected error already
                    if (success != ERR_ENDPT):
                        verified_err.append((endpt, SSL_CMD.format(endpt)))
                        success = WARN_ENDPT

                # neither with nor without certs connected
                connected_err.append((endpt, SSL_CMD.format(endpt)))
                success = ERR_ENDPT

    # if any connection issues found
    if (success == ERR_ENDPT):
        error_info.extend(connected_err)
    # if no connection issues found but some verification issues found
    elif (success == WARN_ENDPT):
        error_info.extend(verified_err)
    return success