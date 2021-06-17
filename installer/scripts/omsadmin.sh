#!/bin/sh

umask 022

set -e

VAR_DIR=/var/opt/microsoft/omsagent
ETC_DIR=/etc/opt/microsoft/omsagent

NPM_DIR=$VAR_DIR/npm_state
NPM_CONF_FILE_SUFFIX=conf/omsagent.d/npmd.conf

DF_TMP_DIR=$VAR_DIR/tmp
DF_RUN_DIR=$VAR_DIR/run
DF_STATE_DIR=$VAR_DIR/state
DF_LOG_DIR=$VAR_DIR/log

DF_CERT_DIR=$ETC_DIR/certs
DF_CONF_DIR=$ETC_DIR/conf

TMP_DIR=$DF_TMP_DIR
CERT_DIR=$DF_CERT_DIR
CONF_DIR=$DF_CONF_DIR
SYSCONF_DIR=$ETC_DIR/sysconf

# Optional file with initial onboarding credentials
FILE_ONBOARD=/etc/omsagent-onboard.conf

# Generated conf file containing information for this script
CONF_OMSADMIN=$CONF_DIR/omsadmin.conf

# Omsagent daemon configuration
CONF_OMSAGENT=$CONF_DIR/omsagent.conf

# Omsagent proxy configuration
CONF_PROXY=$ETC_DIR/proxy.conf
PRE_MH_CONF_PROXY=$DF_CONF_DIR/proxy.conf

# File with OS information for telemetry
OS_INFO=/etc/opt/microsoft/scx/conf/scx-release

# Service Control script
SERVICE_CONTROL=/opt/microsoft/omsagent/bin/service_control

# File with information about the agent installed
INSTALL_INFO=/etc/opt/microsoft/omsagent/sysconf/installinfo.txt

# Ruby helpers
RUBY=/opt/microsoft/omsagent/ruby/bin/ruby
AUTH_KEY_SCRIPT=/opt/microsoft/omsagent/bin/auth_key.rb
TOPOLOGY_REQ_SCRIPT=/opt/microsoft/omsagent/plugin/agent_topology_request_script.rb
MAINTENANCE_TASKS_SCRIPT=/opt/microsoft/omsagent/plugin/agent_maintenance_script.rb
# Ruby error codes
AGENT_MAINTENANCE_MISSING_CONFIG_FILE=4
AGENT_MAINTENANCE_MISSING_CONFIG=5
AGENT_MAINTENANCE_ERROR_WRITING_TO_FILE=12

# DSC MetaConfig generation script
if [ -x "$(command -v python2)" ]; then
    METACONFIG_PY=/opt/microsoft/omsconfig/Scripts/OMS_MetaConfigHelper.py
elif [ -x "$(command -v python3)" ]; then
    METACONFIG_PY=/opt/microsoft/omsconfig/Scripts/python3/OMS_MetaConfigHelper.py
else
    # Failure to find python/the correct script path will only break onboarding (just one
    # of omsadmin's numerous functions); exit with failure in the onboard() function instead
    METACONFIG_PY=""
fi

# Certs
FILE_KEY=$CERT_DIR/oms.key
FILE_CRT=$CERT_DIR/oms.crt

# Temporary files
SHARED_KEY_FILE=$TMP_DIR/shared_key
BODY_ONBOARD=$TMP_DIR/body_onboard.xml
RESP_ONBOARD=$TMP_DIR/resp_onboard.xml
ENDPOINT_FILE=$TMP_DIR/endpoints

AGENT_USER=omsagent
AGENT_GROUP=omiusers

# Default settings
URL_TLD=opinsights.azure.com
WORKSPACE_ID=""
AGENT_GUID=""
LOG_FACILITY=local0
CERTIFICATE_UPDATE_ENDPOINT=""
VERBOSE=0
AZURE_RESOURCE_ID=""
OMSCLOUD_ID=""
UUID=""
USER_ID=`id -u`
MULTI_HOMING_MARKER=

DEFAULT_SYSLOG_PORT=25224
DEFAULT_MONITOR_AGENT_PORT=25324

SYSLOG_PORT=$DEFAULT_SYSLOG_PORT
MONITOR_AGENT_PORT=$DEFAULT_MONITOR_AGENT_PORT

# SCOM variables
SCX_SSL_CONFIG=/opt/microsoft/scx/bin/tools/scxsslconfig
OMI_CONF_FILE=/etc/opt/omi/conf/omiserver.conf
OMI_CONF_EDITOR=/opt/omi/bin/omiconfigeditor

# Space seperated list of non oms workspaces
NON_OMS_WS="scom LAD"

# Error codes and categories:

# User configuration/parameters:
INVALID_OPTION_PROVIDED=2
INVALID_CONFIG_PROVIDED=3
INVALID_PROXY=4
# Service-related:
ERROR_ONBOARDING_403=5
ERROR_ONBOARDING_NON_200_HTTP=6
# Network-related:
ERROR_RESOLVING_HOST=7
ERROR_ONBOARDING=8
# Internal errors:
INTERNAL_ERROR=30
RUBY_ERROR_GENERATING_GUID=31
ERROR_GENERATING_CERTS=32
ERROR_GENERATING_METACONFIG=33
ERROR_METACONFIG_PY_NOT_PRESENT=34
# Dependency-related:
INSTALL_PYTHON=60

# curl error codes:
CURL_PROXY_RESOLVE_ERROR=5
CURL_HOST_RESOLVE_ERROR=6
CURL_CONNECT_HOST_ERROR=7

usage()
{
    local basename=`basename $0`
    echo
    echo "Maintenance tool for OMS:"
    echo "Onboarding:"
    echo "$basename -w <workspace id> -s <shared key> [-d <top level domain>]"
    echo
    echo "List Workspaces:"
    echo "$basename -l"
    echo
    echo "Remove Workspace:"
    echo "$basename -x <workspace id>"
    echo
    echo "Remove All Workspaces:"
    echo "$basename -X"
    echo
    echo "Update workspace configuration and folder structure to multi-homing schema:"
    echo "$basename -U"
    echo
    echo "Onboard the workspace with a multi-homing marker. The workspace will be regarded as secondary."
    echo "$basename -m <multi-homing marker>"
    echo
    echo "Define proxy settings ('-u' will prompt for password):"
    echo "$basename [-u user] -p host[:port]"
    echo
    echo "Azure resource ID:"
    echo "$basename -a <Azure resource ID>"
    echo
    echo "Detect if omiserver is listening to SCOM port:"
    echo "$basename -o"
}

set_user_agent()
{
    USER_AGENT=LinuxMonitoringAgent/`head -1 $INSTALL_INFO | awk '{print $1}'`
}

check_user()
{
    if [ "$USER_ID" -ne "0" -a `id -un` != "$AGENT_USER" ]; then
        log_error "This script must be run as root or as the $AGENT_USER user."
        exit 1
    fi
}

chown_omsagent()
{
    # When this script is run as root, we still have to make sure the generated
    # files are owned by omsagent for everything to work properly
    [ "$USER_ID" -eq "0" ] && chown $AGENT_USER:$AGENT_GROUP $@ > /dev/null 2>&1
    return 0
}

save_config()
{
    #Save configuration
    echo WORKSPACE_ID=$WORKSPACE_ID > $CONF_OMSADMIN
    echo AGENT_GUID=$AGENT_GUID >> $CONF_OMSADMIN
    echo LOG_FACILITY=$LOG_FACILITY >> $CONF_OMSADMIN
    echo CERTIFICATE_UPDATE_ENDPOINT=$CERTIFICATE_UPDATE_ENDPOINT >> $CONF_OMSADMIN
    echo URL_TLD=$URL_TLD >> $CONF_OMSADMIN
    echo DSC_ENDPOINT=$DSC_ENDPOINT >> $CONF_OMSADMIN
    echo OMS_ENDPOINT=https://$WORKSPACE_ID.ods.$URL_TLD/OperationalData.svc/PostJsonDataItems >> $CONF_OMSADMIN
    echo AZURE_RESOURCE_ID=$AZURE_RESOURCE_ID >> $CONF_OMSADMIN
    echo OMSCLOUD_ID=$OMSCLOUD_ID | tr -d ' ' >> $CONF_OMSADMIN
    echo UUID=$UUID | tr -d ' ' >> $CONF_OMSADMIN
    chown_omsagent "$CONF_OMSADMIN"
}

update_azure_resource_id()
{
    sed -i "s,\(AZURE_RESOURCE_ID=\)\(.*\),\1$AZURE_RESOURCE_ID," $CONF_OMSADMIN
    echo "Azure Resource ID updated."
}

cleanup()
{
    rm "$BODY_ONBOARD" "$RESP_ONBOARD" "$ENDPOINT_FILE" > /dev/null 2>&1 || true
}

# This helper should only be called in the cases when certs have been created but onboarding failed.
cleanup_certs()
{
    rm "$FILE_CRT" "$FILE_KEY" > /dev/null 2>&1 || true
}

clean_exit()
{
    cleanup
    exit $1
}

log_info()
{
    echo -e "info\t$1"
    logger -i -p "$LOG_FACILITY".info -t omsagent "[INFO] $1"
}

log_warning()
{
    echo -e "warning\t$1"
    logger -i -p "$LOG_FACILITY".warning -t omsagent "[WARNING] $1"
}

log_error()
{
    echo -e "error\t$1"
    logger -i -p "$LOG_FACILITY".err -t omsagent "[ERROR] $1"
}

parse_args()
{
    local OPTIND opt

    while getopts "h?s:w:d:vp:u:a:lx:XUm:oR" opt; do
        case "$opt" in
        h|\?)
            usage
            clean_exit 0
            ;;
        s)
            ONBOARDING=1
            SHARED_KEY=$OPTARG
            ;;
        w)
            ONBOARDING=1
            WORKSPACE_ID=$OPTARG
            ;;
        d)
            ONBOARDING=1
            URL_TLD=$OPTARG
            ;;
        v)
            VERBOSE=1
            CURL_VERBOSE=-v
            ;;
        p)
            PROXY_HOST=$OPTARG
            ;;
        u)
            PROXY_USER=$OPTARG
            ;;
        a)
            AZURE_RESOURCE_ID=$OPTARG
            ;;
        l)
            LIST_WORKSPACES=1
            ;;
        x)
            REMOVE=1
            WORKSPACE_ID=$OPTARG
            ;;
        X)
            REMOVE_ALL=1
            ;;
        U)
            UPDATE_WORKSPACES=1
            ;;
        m)
            MULTI_HOMING_MARKER=$OPTARG
            ;;
        o)
            DETECT_SCOM=1
            ;;
        R)
            RECONSTRUCT_WORKSPACE_STATE=1
            ;;
        esac
    done
    shift $((OPTIND-1))

    if [ "$@ " != " " ]; then
        log_error "Parsing error: '$@' is unparsed"
        usage
        clean_exit $INVALID_OPTION_PROVIDED
    fi

    if [ -n "$PROXY_USER" -a -z "$PROXY_HOST" ]; then
        log_error "Cannot specify the proxy user without specifying the proxy host"
        usage
        clean_exit $INVALID_PROXY
    fi

    if [ -n "$PROXY_HOST" ]; then
        if [ -n "$PROXY_USER" ]; then
            read -s -p "Proxy password for $PROXY_USER: " PROXY_PASS
            echo
            create_proxy_conf "$PROXY_USER:$PROXY_PASS@$PROXY_HOST"
        else
            create_proxy_conf "$PROXY_HOST"
        fi
    fi

    if [ $VERBOSE -eq 0 ]; then
        # Suppress curl output
        CURL_VERBOSE=-s
    fi
}

create_proxy_conf()
{
    local conf_proxy_content=$1
    touch $CONF_PROXY
    chown_omsagent $CONF_PROXY
    chmod 600 $CONF_PROXY
    echo -n $conf_proxy_content > $CONF_PROXY
    log_info "Created proxy configuration: $CONF_PROXY"
}

copy_proxy_conf_from_pre_mh_loc()
{
    # Expected behavior is to use new proxy location first, then fallback to
    # the pre-multi-homing location, then assume no proxy is configured
    # In future: change from cp to mv once all plugins have been updated to use new location
    if [ -f "$PRE_MH_CONF_PROXY" ]; then
        echo "Moving proxy configuration from file $PRE_MH_CONF_PROXY to $CONF_PROXY..."
        cp -pf $PRE_MH_CONF_PROXY $CONF_PROXY
    fi
}

set_proxy_setting()
{
    if [ -n "$PROXY" ]; then
        PROXY_SETTING="--proxy $PROXY"
        create_proxy_conf "$PROXY"
        return
    fi
    local conf_proxy_content=""
    [ -r "$CONF_PROXY" ] && conf_proxy_content=`cat $CONF_PROXY`
    if [ -n "$conf_proxy_content" ]; then
        PROXY_SETTING="--proxy $conf_proxy_content"
        log_info "Using proxy settings from '$CONF_PROXY'"
    fi
}

is_scom_port_open()
{
    $OMI_CONF_EDITOR httpsport -q 1270 < $OMI_CONF_FILE > /dev/null 2>&1
    if [ $? -eq 1 ]; then
        return 1
    fi
    echo "Port 1270 already open"
    return 0
}

onboard_scom()
{
    echo "Onboarding SCOM"
    create_workspace_directories "scom"

    if [ ! -f $CERT_DIR/scom-cert.pem ] || [ ! -f $CERT_DIR/scom-key.pem ]; then
        echo "Generating SCOM certificates..."
        # Generate client auth cert using scxsslconfig tool.
        $SCX_SSL_CONFIG -c -g $CERT_DIR
        if [ $? -ne 0 ]; then
          log_error "Error generating certs"
          clean_exit 1
        fi
        # Rename cert/key to more meaningful name
        mv $CERT_DIR/omi-host-*.pem $CERT_DIR/scom-cert.pem
        mv $CERT_DIR/omikey.pem $CERT_DIR/scom-key.pem
        rm -f $CERT_DIR/omi.pem
        chown_omsagent $CERT_DIR/scom-cert.pem
        chown_omsagent $CERT_DIR/scom-key.pem
    fi

    touch $CONF_DIR/omsagent.conf
    update_path $CONF_DIR/omsagent.conf
    chown_omsagent $CONF_DIR/*
    make_dir $CONF_DIR/omsagent.d
    #Always register SCOM as secondary Workspace
    echo "SCOM Workspace" > $CONF_DIR/.multihoming_marker
    configure_logrotate

    #Open port 1270 if not already open
    is_scom_port_open
    if [ $? -eq 1 ]; then
        echo "Opening port 1270"
        $OMI_CONF_EDITOR httpsport -a 1270 < $OMI_CONF_FILE > /etc/opt/omi/conf/omiserver.conf_temp
        mv /etc/opt/omi/conf/omiserver.conf_temp $OMI_CONF_FILE
        # Restart OMI
        /opt/omi/bin/service_control restart
    fi
}

onboard_lad()
{
    echo "Onboarding LAD"
    create_workspace_directories "LAD"

    touch $CONF_DIR/omsagent.conf
    echo "@include omsagent.d/*" > $CONF_DIR/omsagent.conf
    chown_omsagent $CONF_DIR/*
    make_dir $CONF_DIR/omsagent.d
    #Always register LAD as secondary Workspace
    echo "LAD Workspace" > $CONF_DIR/.multihoming_marker
    save_config
    configure_logrotate
}

onboard()
{
    if [ "$METACONFIG_PY" = "" ]; then
        echo "Error: Python is not installed on this system, onboarding cannot continue." >&2
        echo "Please install either the python2 or python3 package." >&2
        clean_exit $INSTALL_PYTHON
    fi

    if [ $VERBOSE -eq 1 ]; then
        # Mask the shared key
        local shared_key_trunc=`echo "$SHARED_KEY" | cut -c 1-4 2> /dev/null`
        local shared_key_covered=`echo "$SHARED_KEY" | tr "$SHARED_KEY" "*" | cut -c 5- 2> /dev/null`

        echo "Workspace ID:      $WORKSPACE_ID"
        echo "Shared key:        $shared_key_trunc$shared_key_covered"
        echo "Top Level Domain:  $URL_TLD"
    fi

    if [ "$WORKSPACE_ID" = "scom" ]; then
        onboard_scom
        clean_exit $?
    fi

    if [ "$WORKSPACE_ID" = "LAD" ]; then
        onboard_lad
        clean_exit $?
    fi

    local error=0
    if [ -z "$WORKSPACE_ID" -o -z "$SHARED_KEY" ]; then
        log_error "Missing Workspace ID or Shared Key information for onboarding"
        clean_exit $INVALID_CONFIG_PROVIDED
    fi

    if echo "$WORKSPACE_ID" | grep -Eqv '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'; then
        log_error "The Workspace ID is not valid"
        clean_exit $INVALID_CONFIG_PROVIDED
    fi

    if [ ! -z "$AZURE_RESOURCE_ID" ]; then
        update_azure_resource_id
    fi

    # If a test is not in progress then call service_control to check on the workspace status
    if [ -z "$TEST_WORKSPACE_ID" -a -z "$TEST_SHARED_KEY" ]; then
        $SERVICE_CONTROL is-running $WORKSPACE_ID > /dev/null 2>&1
        if [ $? -eq 1 ]; then
            echo "Workspace $WORKSPACE_ID already onboarded and agent is running."
            if [ -z "$MULTI_HOMING_MARKER" -a ! -h $DF_CONF_DIR ]; then
                echo "Symbolic links have not been created; re-onboarding to create them"
            else
                return 0
            fi
        fi
    fi
    create_workspace_directories $WORKSPACE_ID

    # Guard against blank omsadmin.conf
    local omsadmin_contents="`cat $CONF_OMSADMIN 2> /dev/null`"
    if [ -f $FILE_KEY -a -f $FILE_CRT -a -f $CONF_OMSADMIN -a -n "$omsadmin_contents" ]; then
        # Keep the same agent GUID by loading it from the previous conf
        AGENT_GUID=`grep AGENT_GUID $CONF_OMSADMIN | cut -d= -f2`
        log_info "Reusing previous agent GUID $AGENT_GUID"
    else
        AGENT_GUID=`$RUBY -e "require 'securerandom'; print SecureRandom.uuid"`
        if [ $? -ne 0 -o -z "$AGENT_GUID" ]; then
            log_error "Error generating agent GUID"
            clean_exit $RUBY_ERROR_GENERATING_GUID
        fi

        $RUBY $MAINTENANCE_TASKS_SCRIPT -c "$CONF_OMSADMIN" "$FILE_CRT" "$FILE_KEY" "$RUN_DIR/omsagent.pid" "$CONF_PROXY" "$OS_INFO" "$INSTALL_INFO" -w "$WORKSPACE_ID" -a "$AGENT_GUID" $CURL_VERBOSE
        generate_certs_ret=$?
        if [ $generate_certs_ret -eq $AGENT_MAINTENANCE_MISSING_CONFIG ]; then
            log_error "Error generating certs: missing config"
            clean_exit $INTERNAL_ERROR
        elif [ $generate_certs_ret -ne 0 ]; then
            log_error "Error generating certs"
            clean_exit $ERROR_GENERATING_CERTS
        fi
    fi

    if [ -z "$AGENT_GUID" ]; then
        log_error "AGENT_GUID should not be empty"
        return $INTERNAL_ERROR
    else
        log_info "Agent GUID is $AGENT_GUID"
    fi

    if [ "$VERBOSE" = "1" ]; then
        log_info "Private Key stored in:   $FILE_KEY"
        log_info "Public Key stored in:    $FILE_CRT"
        # Public key can be verified with a command like:  openssl x509 -text -in oms.crt
    fi

    # Generate the body first so we can compute a SHA256 on the body

    REQ_DATE=`date +%Y-%m-%dT%T.%N%:z`
    CERT_SERVER=`cat $FILE_CRT | awk 'NR>2 { print line } { line = $0 }'`

    # append telemetry to $BODY_ONBOARD
    `$RUBY $TOPOLOGY_REQ_SCRIPT -t "$BODY_ONBOARD" "$OS_INFO" "$CONF_OMSADMIN" "$AGENT_GUID" "$CERT_SERVER" "$RUN_DIR/omsagent.pid"`
    [ $? -ne 0 ] && log_error "Error appending Telemetry during Onboarding."

    cat /dev/null > "$SHARED_KEY_FILE"
    chmod 600 "$SHARED_KEY_FILE"
    echo -n "$SHARED_KEY" >> "$SHARED_KEY_FILE"
    AUTHS=`$RUBY $AUTH_KEY_SCRIPT $REQ_DATE $BODY_ONBOARD $SHARED_KEY_FILE`
    rm "$SHARED_KEY_FILE"

    CONTENT_HASH=`echo $AUTHS | cut -d" " -f1`
    AUTHORIZATION_KEY=`echo $AUTHS | cut -d" " -f2`

    if [ $VERBOSE -ne 0 ]; then
        # Mask the certificate in the request
        local body_no_newlines="`cat $BODY_ONBOARD | tr -d '\n' 2> /dev/null`"
        local cert_tag="AuthenticationCertificate"
        local hidden_cert="********"
        echo
        echo "Generated request:"
        echo "$body_no_newlines" | sed "s/<$cert_tag>[^<]*<\/$cert_tag>/<$cert_tag>$hidden_cert<\/$cert_tag>/g"
        echo
    fi

    set_proxy_setting

    if [ "`which dmidecode > /dev/null 2>&1; echo $?`" = 0 ]; then
        UUID=`dmidecode | grep UUID | sed -e 's/UUID: //'`
        OMSCLOUD_ID=`dmidecode | grep "Tag: 77" | sed -e 's/Asset Tag: //'`
    elif [ -f /sys/devices/virtual/dmi/id/chassis_asset_tag ]; then
        ASSET_TAG=$(cat /sys/devices/virtual/dmi/id/chassis_asset_tag)
        case "$ASSET_TAG" in
            77*) OMSCLOUD_ID=$ASSET_TAG ;;       # If the asset tag begins with a 77 this is the azure guid
        esac
        PRODUCT_UUID=$(cat /sys/devices/virtual/dmi/id/product_uuid)
        UUID=$(echo $PRODUCT_UUID | tr '[:upper:]' '[:lower:]')
    fi

    #This is a temporary fix for Systems with Curl versions using HTTP\2 as default
    #Since 7.47.0, the curl tool enables HTTP/2 by default for HTTPS connections. This fix runs curl with --http1.1 on systems with version above 7.47.0
    #Curl http2 Docs Link: https://curl.haxx.se/docs/http2.html
    CURL_VERSION_WITH_DEFAULT_HTTP2="7470"
    CURL_VERSION_SYSTEM=`curl --version | head -c11 | awk '{print $2}' | tr --delete .`
    if [ $CURL_VERSION_SYSTEM -gt $CURL_VERSION_WITH_DEFAULT_HTTP2 ]; then
      CURL_HTTP_COMMAND="--http1.1"
    fi

    RET_CODE=`curl --header "x-ms-Date: $REQ_DATE" \
        --header "x-ms-version: August, 2014" \
        --header "x-ms-SHA256_Content: $CONTENT_HASH" \
        --header "Authorization: $WORKSPACE_ID; $AUTHORIZATION_KEY" \
        --header "User-Agent: $USER_AGENT" \
        --header "Accept-Language: en-US" \
        --insecure \
        $CURL_HTTP_COMMAND \
        --data-binary @$BODY_ONBOARD \
        --cert "$FILE_CRT" --key "$FILE_KEY" \
        --output "$RESP_ONBOARD" $CURL_VERBOSE \
        --write-out "%{http_code}\n" $PROXY_SETTING \
        https://${WORKSPACE_ID}.oms.${URL_TLD}/AgentService.svc/LinuxAgentTopologyRequest` || error=$?

    if [ $error -eq $CURL_HOST_RESOLVE_ERROR -a -z "$PROXY_SETTING" ]; then
        log_error "Error resolving host during the onboarding request. Check the correctness of the workspace ID and the internet connectivity, or add a proxy."
        cleanup_certs
        return $ERROR_RESOLVING_HOST
    elif [ $error -eq $CURL_PROXY_RESOLVE_ERROR -a -n "$PROXY_SETTING" ]; then
        log_error "Proxy could not be resolved during the onboarding request. Verify the proxy."
        cleanup_certs
        return $INVALID_PROXY
    elif [ $error -eq $CURL_CONNECT_HOST_ERROR -a -n "$PROXY_SETTING" ]; then
        log_error "Error connecting to OMS service through proxy. Verify the proxy."
        cleanup_certs
        return $INVALID_PROXY
    elif [ $error -ne 0 ]; then
        log_error "Error during the onboarding request: curl returned $error. Check the correctness of the workspace ID and shared key or run omsadmin.sh with '-v'"
        cleanup_certs
        return $ERROR_ONBOARDING
    fi

    if [ "$RET_CODE" = "200" ]; then
        $RUBY $MAINTENANCE_TASKS_SCRIPT --endpoints "$RESP_ONBOARD","$ENDPOINT_FILE" "$CONF_OMSADMIN" "$FILE_CRT" "$FILE_KEY" "$RUN_DIR/omsagent.pid" "$CONF_PROXY" "$OS_INFO" "$INSTALL_INFO" $CURL_VERBOSE
        endpoints_ret=$?
        if [ $endpoints_ret -eq $AGENT_MAINTENANCE_MISSING_CONFIG_FILE ]; then
            log_error "Onboarding response is missing; certificate update and DSC endpoints were not extracted."
        elif [ $endpoints_ret -eq $AGENT_MAINTENANCE_ERROR_WRITING_TO_FILE ]; then
            log_error "Endpoint file could not be written to; certificate update and DSC endpoints were not saved."
        elif [ $endpoints_ret -ne 0 ]; then
            log_warning "During onboarding request, certificate update and DSC endpoints may not have been saved."
        else
            log_info "Onboarding success"
        fi
        # Get CERTIFICATE_UPDATE_ENDPOINT and DSC_ENDPOINT variables from output file
        if [ -e "$ENDPOINT_FILE" ]; then
            CERTIFICATE_UPDATE_ENDPOINT=`sed -n '1p' < $ENDPOINT_FILE`
            DSC_ENDPOINT=`sed -n '2p' < $ENDPOINT_FILE`
        fi
    elif [ "$RET_CODE" = "403" ]; then
        REASON=`cat $RESP_ONBOARD | sed -n 's:.*<Reason>\(.*\)</Reason>.*:\1:p'`
        log_error "Error onboarding. HTTP code 403, Reason: $REASON. Check the Workspace ID, Workspace Key and that the time of the system is correct."
        cleanup_certs
        return $ERROR_ONBOARDING_403
    else
        log_error "Error onboarding. HTTP code $RET_CODE"
        cleanup_certs
        return $ERROR_ONBOARDING_NON_200_HTTP
    fi

    save_config

    copy_omsagent_conf

    if [ -z "$MULTI_HOMING_MARKER" ]; then
        # update the default folders when onboard to a workspace as primary
        # this is the default behavior
        update_symlinks
    else
        # do not update the default folders when onboard the workspace as secondary
        # leave a marker in the etc folder of the workspace to indicate the partner
        echo $MULTI_HOMING_MARKER > $CONF_DIR/.multihoming_marker
    fi

	#Initialize empty syslog daemon conf file with no default collection
    configure_syslog

    configure_monitor_agent

    configure_logrotate

    # If a test is not in progress then register omsagent as a service and start the agent
    if [ -z "$TEST_WORKSPACE_ID" -a -z "$TEST_SHARED_KEY" ]; then
        $SERVICE_CONTROL start $WORKSPACE_ID

        if [ -z "$MULTI_HOMING_MARKER" ]; then
            # Configure omsconfig when the workspace is primary
            # This is a temp solution since the DSC doesn't support multi-homing now
            # Only the primary workspace receives the configuration from the DSC service

            # Set up a cron job to run the OMSConsistencyInvoker every 15 minutes
            # This should be done regardless of MetaConfig creation
            if [ ! -f /etc/cron.d/OMSConsistencyInvoker ]; then
                randomNo=$(od -An -N1 -i /dev/urandom)
                A=$(($randomNo%13+2))
                B=$(($A+15))
                C=$(($B+15))
                D=$(($C+15))
                echo "$A,$B,$C,$D * * * * $AGENT_USER /opt/omi/bin/OMSConsistencyInvoker >/dev/null 2>&1" > /etc/cron.d/OMSConsistencyInvoker
            fi

            if [ ! -f $METACONFIG_PY ]; then
                log_error "MetaConfig generation script not available at $METACONFIG_PY"
                return $ERROR_METACONFIG_PY_NOT_PRESENT
            fi

            if [ "$USER_ID" -eq "0" ]; then
                su - $AGENT_USER -c $METACONFIG_PY > /dev/null || error=$?

                if [ $error -ne 0 ]; then
                    log_info "Retrying configuring omsconfig by calling '$METACONFIG_PY' with 'sudo'"
                    error=0
                    sudo -u $AGENT_USER $METACONFIG_PY > /dev/null || error=$?
                fi
                
            else
                $METACONFIG_PY > /dev/null || error=$?
            fi

            if [ $error -eq 0 ]; then
                log_info "Configured omsconfig"
            else
                log_error "Error configuring omsconfig. Error: $error"
                return $ERROR_GENERATING_METACONFIG
            fi
        fi
    fi

    return 0
}

remove_workspace()
{
    setup_workspace_variables $WORKSPACE_ID

    if [ -d "$CONF_DIR" ]; then
        log_info "Disable workspace: $WORKSPACE_ID"

        $SERVICE_CONTROL disable $WORKSPACE_ID
    else
        log_error "Workspace $WORKSPACE_ID doesn't exist"
    fi

    log_info "Cleanup the folders"

    local port=$DEFAULT_SYSLOG_PORT
    if [ -e "$CONF_DIR/omsagent.d/syslog.conf" ]; then
        port=`grep 'port .*' $CONF_DIR/omsagent.d/syslog.conf | cut -d ' ' -f4`
    fi

    /opt/microsoft/omsagent/bin/configure_syslog.sh unconfigure $WORKSPACE_ID ${port}

    if [ -f "$NPM_CONF_WS" -a -d "$NPM_DIR" ]; then
        log_info "Removing NPM state directory in $WORKSPACE_ID removal"
        rm -rf $NPM_DIR > /dev/null 2>&1
    fi

    rm -rf "$VAR_DIR_WS" "$ETC_DIR_WS" > /dev/null 2>&1

    rm -f /etc/logrotate.d/omsagent-$WORKSPACE_ID > /dev/null 2>&1

    reset_default_workspace
}

reset_default_workspace()
{
    if [ -h $DF_CONF_DIR -a ! -d $DF_CONF_DIR ]; then
        # default conf folder is removed, remove the symlinks
        rm "$DF_TMP_DIR" "$DF_RUN_DIR" "$DF_STATE_DIR" "$DF_LOG_DIR" "$DF_CERT_DIR" "$DF_CONF_DIR" > /dev/null 2>&1
    fi
}

remove_all()
{
    for ws_id in `ls -1 $ETC_DIR | grep -E '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'`
    do
        WORKSPACE_ID=${ws_id}
        remove_workspace
    done

    # Remove non-OMS "workspaces"
    for ws_id in $NON_OMS_WS
    do
       ls -l $ETC_DIR | grep -w "$ws_id" > /dev/null 2>&1
       if [ $? -eq 0 ]; then
           WORKSPACE_ID="$ws_id"
           remove_workspace
       fi
    done
}

show_workspace_status()
{
    local ws_conf_dir=$1
    local ws_id=$2
    local is_primary=$3
    local status='Unknown'

    # 1 if omsagent-ws_id is running, 0 otherwise
    $SERVICE_CONTROL is-running $ws_id
    if [ $? -eq 1 ]; then
        status='Onboarded(OMSAgent Running)'
    elif [ -f ${ws_conf_dir}/.service_registered ]; then
        status='Warning(OMSAgent Registered, Not Running)'
    elif [ -f ${ws_conf_dir}/omsadmin.conf ]; then
        status='Saved(OMSAgent Not Registered, Workspace Configuration Saved)'
    else
        status='Failure(Agent Not Onboarded, No Workspace Configuration Present)'
    fi

    local mh_marker=
    if [ -f ${ws_conf_dir}/.multihoming_marker ]; then
        mh_marker="(`cat ${ws_conf_dir}/.multihoming_marker`)"
    fi

    if [ ${is_primary} -eq 1 ]; then
        echo "Primary Workspace: ${ws_id}    Status: ${status}"
    else
        echo "Workspace${mh_marker}: ${ws_id}    Status: ${status}"
    fi
}

list_scom_workspace()
{
    ls -1 $ETC_DIR | grep -w scom > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        show_workspace_status $ETC_DIR/scom/conf scom 0
        return 1
    fi
    return 0
}

list_workspaces()
{
    local found_ws=0
    local ws_conf_dir=$ETC_DIR/conf

    if [ -h ${ws_conf_dir} ]; then
        # symbolic link - multiple workspace folder structure
        local primary_ws_id=''
        if [ -f ${ws_conf_dir}/omsadmin.conf ]; then
            primary_ws_id=`grep WORKSPACE_ID ${ws_conf_dir}/omsadmin.conf | cut -d= -f2`
        fi

        if [ "${primary_ws_id}" != "" ]; then
            found_ws=1
            show_workspace_status ${ws_conf_dir} ${primary_ws_id} 1
        fi

        for ws_id in `ls -1 $ETC_DIR | grep -E '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'`
        do
            if [ "${primary_ws_id}" != "${ws_id}" ]; then
                found_ws=1
                show_workspace_status $ETC_DIR/${ws_id}/conf ${ws_id} 0
            fi
        done
    elif [ -d ${ws_conf_dir} ]; then
        # directory - single workspace folder structure
        local ws_id=''

        if [ -f ${ws_conf_dir}/omsadmin.conf ]; then
            ws_id=`grep WORKSPACE_ID ${ws_conf_dir}/omsadmin.conf | cut -d= -f2`
        fi

        if [ "${ws_id}" != "" ]; then
            found_ws=1
            show_workspace_status ${ws_conf_dir} ${ws_id} 1
        fi
    else
        # no default conf folder, check all the potential workspace folders
        for ws_id in `ls -1 $ETC_DIR | grep -E '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'`
        do
            found_ws=1
            show_workspace_status $ETC_DIR/${ws_id}/conf ${ws_id} 0
        done
    fi
    # check scom workspace
    list_scom_workspace
    if [ $? -eq 1 ]; then
        found_ws=1
    fi

    if [ $found_ws -eq 0 ]; then
        echo "No Workspace"
    fi

    return 0
}

migrate_pre_mh_workspace()
{
    if [ -d $DF_CONF_DIR -a ! -h $DF_CONF_DIR -a -f $DF_CONF_DIR/omsadmin.conf ]; then
        WORKSPACE_ID=`grep WORKSPACE_ID $DF_CONF_DIR/omsadmin.conf | cut -d= -f2`

        if [ $? -ne 0 -o -z $WORKSPACE_ID ]; then
            echo "WORKSPACE_ID is not found. Skip migration."
            return
        else
            echo "Migrating to multi-homing folder structure..."
        fi

        create_workspace_directories $WORKSPACE_ID

        cp -rpf $DF_TMP_DIR $VAR_DIR_WS
        cp -rpf $DF_STATE_DIR $VAR_DIR_WS
        cp -rpf $DF_RUN_DIR $VAR_DIR_WS
        cp -rpf $DF_LOG_DIR $VAR_DIR_WS

        cp -rpf $DF_CERT_DIR $ETC_DIR_WS
        cp -rpf $DF_CONF_DIR $ETC_DIR_WS

        copy_omsagent_d_conf

        migrate_pre_mh_omsagent_conf

        sed -i s,%SYSLOG_PORT%,$DEFAULT_SYSLOG_PORT,1 $CONF_DIR/omsagent.d/syslog.conf
        sed -i s,%MONITOR_AGENT_PORT%,$DEFAULT_MONITOR_AGENT_PORT,1 $CONF_DIR/omsagent.d/monitor.conf

        update_symlinks
    elif [ -d $DF_CONF_DIR -a ! -h $DF_CONF_DIR ]; then
        # In some upgrade cases, conf and conf/omsagent.d directories are created and are empty
        # Remove these directories if they are empty
        rmdir $DF_CONF_DIR/omsagent.d 2> /dev/null
        rmdir $DF_CONF_DIR 2> /dev/null
    fi
}

migrate_pre_mh_omsagent_conf()
{
    # migrate the omsagent.conf
    cp -pf $CONF_DIR/omsagent.conf $CONF_DIR/omsagent.conf.bak

    # remove the syslog configuration. it has been moved to omsagent.d/syslog.conf
    cat $CONF_DIR/omsagent.conf.bak | sed '/port 25224/,+4 d' | sed '/<filter oms\.syslog\.\*\*>/,+3 d' | tac | sed '/type syslog/,+1 d' | tac > $CONF_DIR/omsagent.conf

    # update the heartbeat configure to use the fake command
    sed -i s,"command /opt/microsoft/omsagent/bin/omsadmin.sh -b > /dev/null","command echo > /dev/null",1 $CONF_DIR/omsagent.conf

    # add the workspace conf, cert and key to the output plugins
    sed -i s,".*buffer_chunk_limit.*","\n  omsadmin_conf_path $CONF_DIR/omsadmin.conf\n  cert_path $CERT_DIR/oms.crt\n  key_path $CERT_DIR/oms.key\n\n&",g $CONF_DIR/omsagent.conf

    # update the workspace state folder
    sed -i s,"/var/opt/microsoft/omsagent/state",$STATE_DIR,g $CONF_DIR/omsagent.conf
}

update_omsagent_d_conf()
{
    # Parameter: Workspace ID for the folder to update
    setup_workspace_variables $1
    WS_OMSAGENT_D_DIR=$CONF_DIR/omsagent.d
    if [ ! -d "$WS_OMSAGENT_D_DIR" ]; then
        echo "$WS_OMSAGENT_D_DIR does not exist; skipping update in this directory."
        return
    fi

    # Note: if syslog.conf, monitor.conf, or other configuration files using a port must be updated
    # during version upgrade, then new functionality will have to be added here
    copy_no_port_omsagent_d_conf $WS_OMSAGENT_D_DIR
    chown_omsagent $WS_OMSAGENT_D_DIR/*
}

# Update configuration and structure for all configured workspaces
update_workspaces()
{
    local error=0
    # Updating from pre-multi-homing version
    migrate_pre_mh_workspace || error=$?

    # Updating from pre-multi-homing structure (somewhat present in versions >1.3)
    copy_proxy_conf_from_pre_mh_loc || error=$?

    # Updating configuration for all onboarded workspaces to latest shipped versions
    for ws_id in `ls -1 $ETC_DIR | grep -E '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'`
    do
        update_omsagent_d_conf $ws_id || error=$?
    done

    if [ $error -ne 0 ]; then
        clean_exit $error
    fi
}

reconstruct_full_workspace_state()
{
    for ws_id in `ls -1 $ETC_DIR | grep -E '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'`
    do
        WORKSPACE_ID=$ws_id
        setup_workspace_variables $WORKSPACE_ID

        if [ -f $CERT_DIR/oms.key -a -f $CERT_DIR/oms.crt -a -f $CONF_DIR/omsadmin.conf ]; then
            local omsadmin_contents="`cat $CONF_DIR/omsadmin.conf 2> /dev/null`"
            if [ -n "$omsadmin_contents" ]; then
                # Create all workspace-specific directories; if they already exist, this is a NOOP
                create_workspace_directories $WORKSPACE_ID

                # If a test is not in progress, then syslog and logrotate can be set up
                if [ -z "$TEST_WORKSPACE_ID" -a -z "$TEST_SHARED_KEY" ]; then
                    # During omsagent removal, log rotate files are removed; set up log rotate like in onboarding
                    configure_logrotate
                    # Note: we could re-configure syslog here, but it will overwrite user settings in some cases
                fi
            else
                log_warning "Workspace $ws_id has an empty configuration file at $CONF_DIR/omsadmin.conf; please onboard to populate this configuration"
            fi
        else
            log_warning "Workspace $ws_id has created a folder $ETC_DIR/$ws_id, but is missing certificates or configuration; please onboard"
        fi
    done
}

setup_workspace_variables()
{
    VAR_DIR_WS=$VAR_DIR/$1
    ETC_DIR_WS=$ETC_DIR/$1

    TMP_DIR=$VAR_DIR_WS/tmp
    STATE_DIR=$VAR_DIR_WS/state
    RUN_DIR=$VAR_DIR_WS/run
    LOG_DIR=$VAR_DIR_WS/log
    CERT_DIR=$ETC_DIR_WS/certs
    CONF_DIR=$ETC_DIR_WS/conf

    NPM_CONF_WS=$ETC_DIR/$1/$NPM_CONF_FILE_SUFFIX
}

create_workspace_directories()
{
    setup_workspace_variables $1

    make_dir $VAR_DIR_WS
    make_dir $ETC_DIR_WS

    make_dir $TMP_DIR
    make_dir $STATE_DIR
    make_dir $RUN_DIR
    make_dir $LOG_DIR
    make_dir $CERT_DIR
    make_dir $CONF_DIR

    chmod 700 $CERT_DIR

    # Generated conf file containing information for this script
    CONF_OMSADMIN=$CONF_DIR/omsadmin.conf

    # Omsagent daemon configuration
    CONF_OMSAGENT=$CONF_DIR/omsagent.conf

    # Certs
    FILE_KEY=$CERT_DIR/oms.key
    FILE_CRT=$CERT_DIR/oms.crt

    # Temporary files
    SHARED_KEY_FILE=$TMP_DIR/shared_key
    BODY_ONBOARD=$TMP_DIR/body_onboard.xml
    RESP_ONBOARD=$TMP_DIR/resp_onboard.xml
    ENDPOINT_FILE=$TMP_DIR/endpoints
}

make_dir()
{
    if [ ! -d $1 ]; then
        mkdir -m 750 $1
    else
        if [ $VERBOSE -eq 1 ]; then
            echo "Directory $1 already exists."
        fi
        chmod 750 $1
    fi

    chown_omsagent $1
}

copy_omsagent_conf()
{
    cp -p $SYSCONF_DIR/omsagent.conf $CONF_DIR

    update_path $CONF_DIR/omsagent.conf

    chown_omsagent $CONF_DIR/*

    copy_omsagent_d_conf
}

copy_omsagent_d_conf()
{
    OMSAGENTD_DIR=$CONF_DIR/omsagent.d
    make_dir $OMSAGENTD_DIR

    cp -p $SYSCONF_DIR/omsagent.d/monitor.conf $OMSAGENTD_DIR
    cp -p $SYSCONF_DIR/omsagent.d/syslog.conf $OMSAGENTD_DIR

    update_path $OMSAGENTD_DIR/monitor.conf

    copy_no_port_omsagent_d_conf $OMSAGENTD_DIR

    chown_omsagent $OMSAGENTD_DIR/*
}

copy_no_port_omsagent_d_conf()
{
    # Copy configuration files from sysconf to a workspace-specific omsagent.d directory
    # which do not depend on a workspace-specific port being set
    # Parameter: workspace-specific omsagent.d directory
    cp -p $SYSCONF_DIR/omsagent.d/heartbeat.conf $1
    cp -p $SYSCONF_DIR/omsagent.d/telemetry.conf $1
    cp -p $SYSCONF_DIR/omsagent.d/operation.conf $1
    cp -p $SYSCONF_DIR/omi_mapping.json $1
    cp -p $SYSCONF_DIR/omsagent.d/container.conf $1 2> /dev/null

    update_path $1/heartbeat.conf
    update_path $1/telemetry.conf
    update_path $1/operation.conf
    if [ -f $1/container.conf ] ; then
        update_path $1/container.conf
    fi
}

update_path()
{
    sed -i s,%CONF_DIR_WS%,$CONF_DIR,1 $1
    sed -i s,%CERT_DIR_WS%,$CERT_DIR,1 $1
    sed -i s,%TMP_DIR_WS%,$TMP_DIR,1 $1
    sed -i s,%RUN_DIR_WS%,$RUN_DIR,1 $1
    sed -i s,%STATE_DIR_WS%,$STATE_DIR,1 $1
    sed -i s,%LOG_DIR_WS%,$LOG_DIR,1 $1
}

update_symlinks()
{
    link_dir $DF_TMP_DIR $TMP_DIR
    link_dir $DF_RUN_DIR $RUN_DIR
    link_dir $DF_STATE_DIR $STATE_DIR
    link_dir $DF_LOG_DIR $LOG_DIR

    link_dir $DF_CERT_DIR $CERT_DIR
    link_dir $DF_CONF_DIR $CONF_DIR
}

link_dir()
{
    if [ -d $1 ]; then
        rm -r $1
    fi

    ln -s $2 $1

    chown_omsagent $1
}

find_available_port()
{
    local port=$1
    local result=$2
    if [ "`which netstat > /dev/null 2>&1; echo $?`" = 0 ]; then
        until [ -z "`netstat -an | grep ${port}`" -a -z "`grep ${port} $ETC_DIR/*/conf/omsagent.d/*.conf`" ]; do
            port=$((port+1))
        done
    else
        log_info "netstat tool is not available. Default port defined in omsadmin.sh will be used."
    fi

    eval $result="${port}"
}

configure_syslog()
{
    echo "Configure syslog..."
    find_available_port $DEFAULT_SYSLOG_PORT SYSLOG_PORT

    sed -i s,%SYSLOG_PORT%,$SYSLOG_PORT,1 $CONF_DIR/omsagent.d/syslog.conf

    /opt/microsoft/omsagent/bin/configure_syslog.sh configure $WORKSPACE_ID $SYSLOG_PORT
}

configure_monitor_agent()
{
    echo "Configure heartbeat monitoring agent..."
    find_available_port $DEFAULT_MONITOR_AGENT_PORT MONITOR_AGENT_PORT

    sed -i s,%MONITOR_AGENT_PORT%,$MONITOR_AGENT_PORT,1 $CONF_DIR/omsagent.d/monitor.conf
}

configure_logrotate()
{
    echo "Configure log rotate for workspace $WORKSPACE_ID..."

    # create the logrotate file for omsagent if workspace is LAD
    if [ "$WORKSPACE_ID" = "LAD" ]; then
        # create the logrotate file for the LAD if it doesn't exist
    	if [ ! -f /etc/logrotate.d/omsagent-$WORKSPACE_ID ]; then
            cp $SYSCONF_DIR/lad-logrotate.conf  /etc/logrotate.d/omsagent-$WORKSPACE_ID
    	fi
    else
    	# create the logrotate file for the workspace if it doesn't exist
    	if [ ! -f /etc/logrotate.d/omsagent-$WORKSPACE_ID ]; then
            cat $SYSCONF_DIR/logrotate.conf | sed "s/%WORKSPACE_ID%/$WORKSPACE_ID/g" > /etc/logrotate.d/omsagent-$WORKSPACE_ID
    	fi
    fi

    # Label omsagent log files according to selinux policy module for logrotate if selinux is present
    SEPKG_DIR_OMSAGENT=/usr/share/selinux/packages/omsagent-logrotate
    if [ -e /usr/sbin/semodule -a -d "$SEPKG_DIR_OMSAGENT" ]; then
        # Label omsagent log file for this $WORKSPACE_ID
        /sbin/restorecon -R $VAR_DIR/*/log > /dev/null 2>&1
    fi
}

main()
{
    check_user
    set_user_agent
    parse_args $@

    if [ $# -eq 0 ] || [ $# -eq 1 -a "$VERBOSE" = "1" ]; then

        # Allow onboarding params to be loaded from a file
        # The file contains at least these two lines :
        # WORKSPACE_ID="[...]"
        # SHARED_KEY="[...]"

        if [ -r "$FILE_ONBOARD" ]; then
            log_info "Reading onboarding params from: $FILE_ONBOARD"
            . "$FILE_ONBOARD"
            ONBOARDING=1
            ONBOARD_FROM_FILE=1
        else
            usage
            clean_exit $INVALID_OPTION_PROVIDED
        fi
    fi

    if [ "$DETECT_SCOM" = "1" ]; then
        is_scom_port_open > /dev/null 2>&1
        clean_exit $?
    fi

    if [ "$ONBOARDING" = "1" ]; then
        onboard || clean_exit $?
    fi

    if [ "$LIST_WORKSPACES" = "1" ]; then
        list_workspaces || clean_exit 1
    fi

    if [ "$UPDATE_WORKSPACES" = "1" ]; then
        update_workspaces || clean_exit $?
    fi

    if [ "$RECONSTRUCT_WORKSPACE_STATE" = "1" ]; then
        reconstruct_full_workspace_state || clean_exit $?
    fi

    if [ "$REMOVE" = "1" ]; then
        remove_workspace || clean_exit 1
    fi

    if [ "$REMOVE_ALL" = "1" ]; then
        remove_all || clean_exit 1
    fi

    # If we reach this point, onboarding was successful, we can remove the
    # onboard conf to prevent accidentally re-onboarding
    [ "$ONBOARD_FROM_FILE" = "1" ] && rm "$FILE_ONBOARD" > /dev/null 2>&1 || true

    clean_exit 0
}

main $@
