#! /bin/sh

#
# Shell Bundle installer package for the OMS project
#

# This script is a skeleton bundle file for ULINUX only for project OMS.

PATH=/sbin:/bin:/usr/sbin:/usr/bin
umask 022

# Can't use something like 'readlink -e $0' because that doesn't work everywhere
# And HP doesn't define $PWD in a sudo environment, so we define our own
case $0 in
    /*|~*)
        SCRIPT_INDIRECT="`dirname $0`"
        ;;
    *)
        PWD="`pwd`"
        SCRIPT_INDIRECT="`dirname $PWD/$0`"
        ;;
esac

SCRIPT_DIR="`(cd \"$SCRIPT_INDIRECT\"; pwd -P)`"
SCRIPT="$SCRIPT_DIR/`basename $0`"
EXTRACT_DIR="`pwd -P`/omsbundle.$$"
ONBOARD_FILE=/etc/omsagent-onboard.conf
DPKG_CONF_QUALS="--force-confold --force-confdef"
OMISERV_CONF="/etc/opt/omi/conf/omiserver.conf"
OLD_OMISERV_CONF="/etc/opt/microsoft/scx/conf/omiserver.conf"
OMS_RUBY_DIR="/opt/microsoft/omsagent/ruby/bin"
OMS_ENV_FILE="/etc/opt/microsoft/omsagent/omsagent.env"
OMS_CONSISTENCY_INVOKER="/etc/cron.d/OMSConsistencyInvoker"
OMI_SERVICE="/opt/omi/bin/service_control"
BIN_PATH="/opt/microsoft/omsagent/bin/"
TST_EXTRACT_DIR="`pwd -P`/tst_omsbundle.$$"
TST_PATH="${BIN_PATH}/troubleshooter"
TST_MODULES_PATH="/opt/microsoft/omsagent/tst"
PURGE_SCRIPT_PATH="${BIN_PATH}/purge_omsagent.sh"

TST_PKG="https://raw.github.com/microsoft/OMS-Agent-for-Linux/master/source/code/troubleshooter/omsagent_tst.tar.gz"
TST_DOCS="https://github.com/microsoft/OMS-Agent-for-Linux/blob/master/docs/Troubleshooting-Tool.md"
PURGE_SCRIPT_PKG="https://raw.github.com/microsoft/OMS-Agent-for-Linux/master/tools/purge_omsagent.sh"

# These symbols will get replaced during the bundle creation process.

TAR_FILE=<TAR_FILE>
OMS_PKG=<OMS_PKG>
DSC_PKG=<DSC_PKG>
OMI_PKG=<OMI_PKG>
SCX_PKG=<SCX_PKG>
INSTALL_TYPE=<INSTALL_TYPE>
SCRIPT_LEN=<SCRIPT_LEN>
SCRIPT_LEN_PLUS_ONE=<SCRIPT_LEN+1>

# Error codes and categories:

# User configuration/parameters:
INVALID_OPTION_PROVIDED=2
NO_OPTION_PROVIDED=3
INVALID_PACKAGE_TYPE=4
RUN_AS_ROOT=5
INVALID_PACKAGE_ARCH=6
# Accompanying packages issues:
OMS_INSTALL_FAILED=17
DSC_INSTALL_FAILED=18
OMI_INSTALL_FAILED=19
SCX_INSTALL_FAILED=20
SCX_KITS_INSTALL_FAILED=21
BUNDLED_INSTALL_FAILED=22
USE_UPGRADE=23
# Internal errors:
INTERNAL_ERROR=30
# Package pre-requisites fail
DEPENDENCY_MISSING=52 #https://github.com/Azure/azure-marketplace/wiki/Extension-Build-Notes-Best-Practices#error-codes-and-messages-output-to-stderr
UNSUPPORTED_OPENSSL=55 #60, temporary as 55 excludes from SLA
INSTALL_PYTHON=60
INSTALL_PYTHON_CTYPES=61
INSTALL_TAR=62
INSTALL_SED=63
INSTALL_CURL=55 #64, temporary as 55 excludes from SLA
INSTALL_GPG=65
UNSUPPORTED_PKG_INSTALLER=66
OPENSSL_PATH="openssl"
BUNDLES_PATH="bundles"
BUNDLES_LEGACY_PATH="bundles/v1"

usage()
{
    echo "usage: $1 [OPTIONS]"
    echo "Options:"
    echo "  --extract                  Extract contents and exit."
    echo "  --force                    Force upgrade (override version checks)."
    echo "  --install                  Install the package from the system."
    echo "  --purge                    Uninstall the package and remove all related data."
    echo "  --restart-deps             Reconfigure and restart dependent service(s)."
    echo "  --source-references        Show source code reference hashes."
    echo "  --upgrade                  Upgrade the package in the system."
    echo "  --enable-opsmgr            Enable port 1270 for usage with opsmgr."
    echo "  --version                  Version of this shell bundle."
    echo "  --version-check            Check versions already installed to see if upgradable."
    echo "  --debug                    use shell debug mode."
    echo
    echo "  -w id, --id id             Use workspace ID <id> for automatic onboarding."
    echo "  -s key, --shared key       Use <key> as the shared key for automatic onboarding."
    echo "  -d dmn, --domain dmn       Use <dmn> as the OMS domain for onboarding. Optional."
    echo "                             default: opinsights.azure.com"
    echo "                             ex: opinsights.azure.us (for FairFax)"
    echo "  -p conf, --proxy conf      Use <conf> as the proxy configuration."
    echo "                             ex: -p [protocol://][user:password@]proxyhost[:port]"
    echo "  -a id, --azure-resource id Use Azure Resource ID <id>."
    echo "  -m marker, --multi-homing-marker marker"
    echo "                             Onboard as a multi-homing(Non-Primary) workspace."
    echo
    echo "  -? | -h | --help           shows this usage text."
}

source_references()
{
    cat <<EOF
-- Source code references --
EOF
}

cleanup_and_exit()
{
    # $1: Exit status
    # $2: Non-blank (if we're not to delete bundles), otherwise empty

    # check if troubleshooter should be installed
    if [ ! -z "$INSTALL_TST" ]; then
        set +e
        install_troubleshooter
        # download purge script as well
        install_purge_script
        set -e
    fi

    if [ -z "$2" -a -d "$EXTRACT_DIR" ]; then
        cd $EXTRACT_DIR/..
        rm -rf $EXTRACT_DIR
    fi

    if [ -n "$1" ]; then
        echo "Shell bundle exiting with code $1"
        exit $1
    else
        exit 0
    fi
}

check_version_installable()
{
    # POSIX Semantic Version <= Test
    # Exit code 0 is true (i.e. installable).
    # Exit code non-zero means existing version is >= version to install.
    #
    # Parameter:
    #   Installed: "x.y.z.b" (like "4.2.2.135"), for major.minor.patch.build versions
    #   Available: "x.y.z.b" (like "4.2.2.135"), for major.minor.patch.build versions

    if [ $# -ne 2 ]; then
        echo "INTERNAL ERROR: Incorrect number of parameters passed to check_version_installable" >&2
        cleanup_and_exit $INTERNAL_ERROR
    fi

    # Current version installed
    local INS_MAJOR=`echo $1 | cut -d. -f1`
    local INS_MINOR=`echo $1 | cut -d. -f2`
    local INS_PATCH=`echo $1 | cut -d. -f3`
    local INS_BUILD=`echo $1 | cut -d. -f4`

    # Available version number
    local AVA_MAJOR=`echo $2 | cut -d. -f1`
    local AVA_MINOR=`echo $2 | cut -d. -f2`
    local AVA_PATCH=`echo $2 | cut -d. -f3`
    local AVA_BUILD=`echo $2 | cut -d. -f4`

    # Check bounds on MAJOR
    if [ $INS_MAJOR -lt $AVA_MAJOR ]; then
        return 0
    elif [ $INS_MAJOR -gt $AVA_MAJOR ]; then
        return 1
    fi

    # MAJOR matched, so check bounds on MINOR
    if [ $INS_MINOR -lt $AVA_MINOR ]; then
        return 0
    elif [ $INS_MINOR -gt $AVA_MINOR ]; then
        return 1
    fi

    # MINOR matched, so check bounds on PATCH
    if [ $INS_PATCH -lt $AVA_PATCH ]; then
        return 0
    elif [ $INS_PATCH -gt $AVA_PATCH ]; then
        return 1
    fi

    # PATCH matched, so check bounds on BUILD
    if [ $INS_BUILD -lt $AVA_BUILD ]; then
        return 0
    elif [ $INS_BUILD -gt $AVA_BUILD ]; then
        return 1
    fi

    # Version available is idential to installed version, so don't install
    return 1
}

getVersionNumber()
{
    # Parse a version number from a string.
    #
    # Parameter 1: string to parse version number string from
    #     (should contain something like mumble-4.2.2.135.universal.x86.tar)
    # Parameter 2: prefix to remove ("mumble-" in above example)

    if [ $# -ne 2 ]; then
        echo "INTERNAL ERROR: Incorrect number of parameters passed to getVersionNumber" >&2
        cleanup_and_exit $INTERNAL_ERROR
    fi

    echo $1 | sed -e "s/$2//" -e 's/\.universal\..*//' -e 's/\.x64.*//' -e 's/\.x86.*//' -e 's/-/./'
}

verifyNoInstallationOption()
{
    if [ -n "${installMode}" ]; then
        echo "$0: Conflicting qualifiers, exiting" >&2
        cleanup_and_exit $INVALID_OPTION_PROVIDED
    fi

    return;
}

verifyPrivileges()
{
    # Parameter: desired operation (for meaningful output)
    if [ -z "$1" ]; then
        echo "INTERNAL ERROR: verifyPrivileges missing required parameter (operation)" 1>& 2
        exit $INTERNAL_ERROR
    fi

    if [ `id -u` -ne 0 ]; then
        echo "Must have root privileges to be able to perform $1 operation" 1>& 2
        exit $RUN_AS_ROOT
    fi
}

is_suse11_platform_with_openssl1(){
  if [ -e /etc/SuSE-release ];then
     VERSION=`cat /etc/SuSE-release|grep "VERSION = 11"|awk 'FS=":"{print $3}'`
     if [ ! -z "$VERSION" ];then
        which openssl1>/dev/null 2>&1
        if [ $? -eq 0 -a $VERSION -eq 11 ];then
           return 0
        fi
     fi
  fi
  return 1
}

detect_cylance(){
  # Don't use 'service' to check the existance of a service
  # because it will fail if there is no service available 
  
  [ -f /etc/init.d/cylance ] && return 0
  [ -f /etc/init.d/cylancesvc ] && return 0
  [ -d /opt/cylance ] && return 0

  return 1
}

# Cylance is conflicting with jemalloc
# only disable jemalloc when cylance is present
disable_jemalloc_if_cylance_exist(){
  if detect_cylance; then
    echo "Cylance detected, disabling jemalloc..."
    sed -i 's/^LD_PRELOAD=/#LD_PRELOAD=/g' $OMS_ENV_FILE
  fi
}

ulinux_detect_openssl_version()
{
    is_suse11_platform_with_openssl1
    if [ $? -eq 0 ];then
       OPENSSL_PATH="openssl1"
    fi

    TMPBINDIR=
    # the system OpenSSL version is 1.0.0.  Likewise with OPENSSL_SYSTEM_VERSION_11X
    OPENSSL_SYSTEM_VERSION_FULL=`$OPENSSL_PATH version | awk '{print $2}'`
    OPENSSL_SYSTEM_VERSION_10X=`echo $OPENSSL_SYSTEM_VERSION_FULL | grep -Eq '^1.0.'; echo $?`
    OPENSSL_SYSTEM_VERSION_100_ONLY=`echo $OPENSSL_SYSTEM_VERSION_FULL | grep -Eq '^1.0.0'; echo $?`
    OPENSSL_SYSTEM_VERSION_11X=`echo $OPENSSL_SYSTEM_VERSION_FULL | grep -Eq '^1.1.'; echo $?`

    if [ $OPENSSL_SYSTEM_VERSION_100_ONLY = 1 ] && [ $OPENSSL_SYSTEM_VERSION_10X = 0 ]; then
        TMPBINDIR=100
    elif [ $OPENSSL_SYSTEM_VERSION_11X = 0 ]; then
        TMPBINDIR=110
    else
        echo "Error: This system does not have a supported version of OpenSSL installed."
        echo "This system's OpenSSL version: $OPENSSL_SYSTEM_VERSION_FULL"
        echo "Supported versions: 1.0.1 onward (1.0.0 was deprecated), 1.1.*"
        cleanup_and_exit $UNSUPPORTED_OPENSSL
    fi
}

ulinux_detect_installer()
{
    INSTALLER=""

    # Detect based on distribution
    if [ -f "/etc/debian_version" ]; then # Ubuntu, Debian
        INSTALLER="DPKG"
    elif [ -f "/etc/redhat-release" ]; then # RHEL, CentOS, Oracle
        INSTALLER="RPM"
    elif [ -f "/etc/os-release" ]; then # Possibly SLES, openSUSE
        grep PRETTY_NAME /etc/os-release | sed 's/PRETTY_NAME=//g' | tr -d '="' | grep -qi suse
        if [ $? == 0 ]; then
            INSTALLER="RPM"
        fi
    fi

    # Fall back on detection via package manager availability
    if [ "$INSTALLER" = "" ]; then
        if [ -x "$(command -v dpkg)" ]; then
            INSTALLER="DPKG"
        elif [ -x "$(command -v rpm)" ]; then
            INSTALLER="RPM"
        fi
    fi

    if [ "$INSTALLER" = "" ]; then
        echo "Error: This system does not have a supported package manager" >&2
        echo "Supported Sytems: 'DPKG' & 'RPM'" >&2
        cleanup_and_exit $UNSUPPORTED_PKG_INSTALLER
    fi
}

# $1 - The name of the package to check as to whether it's installed
check_if_pkg_is_installed()
{
    if [ "$INSTALLER" = "DPKG" ]; then
        dpkg -s $1 2> /dev/null | grep Status | grep " installed" 1> /dev/null
    else
        rpm -q $1 > /dev/null 2>&1
    fi

    return $?
}

check_if_program_in_path()
{
    # Parameter: name of program to check
    # Returns: 0 if program is in path, non-zero if not
    if [ $# -ne 1 ]; then
        echo "INTERNAL ERROR: Incorrect number of parameters passed to check_if_program_in_path" >&2
        cleanup_and_exit $INTERNAL_ERROR
    fi
    which $1 > /dev/null 2>&1
    return $?
}

check_if_program_exists_on_system()
{
    # Parameters: $1 - name of program to check
    # Returns: 0 if program is in system or installed as a package, 1 if not
    if [ $# -ne 1 ]; then
        echo "INTERNAL ERROR: Incorrect number of parameters passed to check_if_program_exists_on_system" >&2
        cleanup_and_exit $INTERNAL_ERROR
    fi
    local exists=1
    check_if_pkg_is_installed $1
    [ $? -eq 0 ] && exists=0
    check_if_program_in_path $1
    [ $? -eq 0 ] && exists=0
    return $exists
}

install_if_program_does_not_exist_on_system()
{
    # Parameters: $1 - name of program to check and possibly install
    # Returns: 0 if program is in system or installed as a package, 1 if not
    if [ $# -ne 1 ]; then
        echo "INTERNAL ERROR: Incorrect number of parameters passed to install_if_program_does_not_exist_on_system" >&2
        cleanup_and_exit $INTERNAL_ERROR
    fi

    check_if_program_exists_on_system $1
    if [ $? -eq 0 ]; then
        return 0
    fi

    echo "$1 was not found; attempting to install $1..."
    install_extra_package $1
    if [ $? -eq 0 ]; then
        return 0
    else
        # If package installation did not succeed, return the check status in case it's changed
        check_if_program_exists_on_system $1
        return $?
    fi
}

install_troubleshooter()
{
    # check if troubleshooter installed successfully via shell bundle
    if [ ! -f "$TST_PATH" -o ! -d "$TST_MODULES_PATH" ]; then
        # install troubleshooter if not successfully installed using shell bundle
        echo "OMS Troubleshooter not installed using shell bundle, will try to install using wget."
        echo "----- Installing troubleshooter -----"

        # create temp directory
        mkdir -p $TST_EXTRACT_DIR
        cd $TST_EXTRACT_DIR

        # grab tst bundle
        echo "Grabbing troubleshooter bundle from Github..."
        wget $TST_PKG > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "Error downloading troubleshooter. To install it manually, please go to the below link:"
            echo ""
            echo $TST_DOCS
            echo ""
            cd ${TST_EXTRACT_DIR}/..
            rm -rf $TST_EXTRACT_DIR
            return 0
        fi

        echo "Unzipping troubleshooter bundle..."
        tar -xzf omsagent_tst.tar.gz > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "Error unzipping troubleshooter bundle. To install it manually, please go to the below link:"
            echo ""
            echo $TST_DOCS
            echo ""
            cd ${TST_EXTRACT_DIR}/..
            rm -rf $TST_EXTRACT_DIR
            return 0
        fi

        # copy over tst files
        echo "Copying over troubleshooter files..."
        mkdir -p $TST_MODULES_PATH
        cp -r modules $TST_MODULES_PATH
        mkdir -p $BIN_PATH
        cp troubleshooter $BIN_PATH

        # verify everything installed correctly
        if [ ! -f "$TST_PATH" -o ! -d "${TST_MODULES_PATH}/modules" ]; then
            echo "Error copying files over for troubleshooter. To install it manually, please go to the below link:"
            echo ""
            echo $TST_DOCS
            echo ""
            cd ${TST_EXTRACT_DIR}/..
            rm -rf $TST_EXTRACT_DIR
            return 0
        fi

        cd ${TST_EXTRACT_DIR}/..
        rm -rf $TST_EXTRACT_DIR
    fi

    echo "OMS Troubleshooter is installed."
    echo "You can run the Troubleshooter with the following command:"
    echo ""
    echo "  $ sudo /opt/microsoft/omsagent/bin/troubleshooter"
    echo ""
        
    return 0
}

install_purge_script()
{
    # check if purge script is already installed
    if [ ! -f "$PURGE_SCRIPT_PATH" ]; then
        echo "Purge script not installed using shell bundle, will try to install using wget."
        mkdir -p $BIN_PATH
        wget -P $BIN_PATH $PURGE_SCRIPT_PKG > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "Error downloading purge script. Please download it manually from the following location:"
            echo ""
            echo $PURGE_SCRIPT_PKG
            echo ""
            return 0
        fi
    fi

    return 0
}

isDiskSpaceSufficient()
{
    local pkg_filename=$1

    if [ ! -d "/opt" ]; then
        spaceAvailableOpt=`expr $(stat -f --printf="%a" /) \* $(stat -f --printf="%s" /)`
    else
        spaceAvailableOpt=`expr $(stat -f --printf="%a" /opt) \* $(stat -f --printf="%s" /opt)`
    fi

    if [ $? -ne 0 -o "$spaceAvailableOpt"a = ""a ]; then
        return 1
    fi

    if [ "$INSTALLER" = "DPKG" ]; then
         spaceRequired=`dpkg -f $pkg_filename Installed-Size 2>/dev/null`
         if [ $? -ne 0 -o "$spaceRequired"a = ""a ]; then
             return 1
         fi
         spaceRequired=`expr $spaceRequired \* 1024`
    else
         spaceRequired=`rpm --queryformat='%12{SIZE}  %{NAME}\n' -qp $pkg_filename|awk '{print $1}' 2>/dev/null`
         if [ $? -ne 0 -o "$spaceRequired"a = ""a ]; then
             return 1
         fi
    fi

    if [ $spaceAvailableOpt -gt $spaceRequired ]; then
        return 0
    fi
    return 1
}

# $1 - The filename of the package to be installed
# $2 - The package name of the package to be installed (for future compatibility)
pkg_add()
{
    pkg_filename=$1
    pkg_name=$2

    echo "----- Installing package: $pkg_name ($pkg_filename) -----"

    ulinux_detect_openssl_version
    pkg_filename=$TMPBINDIR/$pkg_filename

    if [ "$INSTALLER" = "DPKG" ]; then
        [ -z "${forceFlag}" ] && FORCE="--refuse-downgrade" || FORCE=""
        isDiskSpaceSufficient ${pkg_filename}.deb
        if [ $? -ne 0 ]; then
           return $DEPENDENCY_MISSING
        fi

        dpkg ${DPKG_CONF_QUALS} --install $FORCE ${pkg_filename}.deb
        return $?
    else
        [ -n "${forceFlag}" ] && FORCE="--force" || FORCE=""
        isDiskSpaceSufficient ${pkg_filename}.rpm
        if [ $? -ne 0 ]; then
           return $DEPENDENCY_MISSING
        fi

        rpm -ivh $FORCE ${pkg_filename}.rpm
        return $?
    fi
}

# $1 - The package name of the package to be uninstalled
pkg_rm()
{
    echo "----- Removing package: $1 -----"
    if [ "$INSTALLER" = "DPKG" ]; then
        if [ "$installMode" = "P" ]; then
            dpkg --purge ${1}
        else
			# for OMI alone, always purge so that config is removed
			if [ "$1" = "omi" ]; then
				dpkg --purge ${1}
			else
				dpkg --remove ${1}
			fi
        fi
    else
        rpm --erase ${1}
    fi
    if [ $? -ne 0 ]; then
        echo "----- Ignore previous errors for package: $1 -----"
    fi
}


# $1 - The filename of the package to be installed
# $2 - The package name of the package to be installed
# $3 - Okay to upgrade the package? (Optional)
pkg_upd() {
    pkg_filename=$1
    pkg_name=$2
    pkg_allowed=$3

    echo "----- Upgrading package: $pkg_name ($pkg_filename) -----"

    if [ -z "${forceFlag}" -a -n "$pkg_allowed" ]; then
        if [ $pkg_allowed -ne 0 ]; then
            echo "Skipping package since existing version >= version available"
            return 0
        fi
    fi

    ulinux_detect_openssl_version
    pkg_filename=$TMPBINDIR/$pkg_filename

    if [ "$INSTALLER" = "DPKG" ]
    then
        [ -z "${forceFlag}" ] && FORCE="--refuse-downgrade" || FORCE=""
        dpkg ${DPKG_CONF_QUALS} --install $FORCE ${pkg_filename}.deb
        return $?
    else
        [ -n "${forceFlag}" ] && FORCE="--force" || FORCE=""
        rpm --upgrade $FORCE ${pkg_filename}.rpm
        return $?
    fi
}

get_arch()
{
    if [ $(getconf LONG_BIT) = 64 ]; then
        echo "x64"
    else
        echo "x86"
    fi
}

compare_arch()
{
    # Check if the user is trying to install the correct bundle (x64 vs. x86)
    echo "Checking host architecture ..."
    HOST_ARCH=$(get_arch)

    case $OMS_PKG in
        *"$HOST_ARCH")
            ;;
        *)
            echo "Cannot install $OMS_PKG on ${HOST_ARCH} platform"
            cleanup_and_exit $INVALID_PACKAGE_ARCH
            ;;
    esac
}

compare_install_type()
{
    # If the bundle has an INSTALL_TYPE, check if the bundle being installed
    # matches the installer on the machine (rpm vs.dpkg)
    if [ ! -z "$INSTALL_TYPE" ]; then
        if [ $INSTALLER != $INSTALL_TYPE ]; then
           echo "This kit is intended for ${INSTALL_TYPE} systems and cannot install on ${INSTALLER} systems"
           cleanup_and_exit $INVALID_PACKAGE_TYPE
        fi
    fi
}

get_python_command()
{
    if [ -x "$(command -v python2)" ]; then
        echo "python2"
    elif [ -x "$(command -v python3)" ]; then
        echo "python3"
    else
        echo ""
    fi
}

python_installed()
{
    PYTHON=$(get_python_command)
    if [ "$PYTHON" != "" ]; then
        return 0
    else
        return 1
    fi
}

python_ctypes_installed()
{
    # Check for Python ctypes library (required for omsconfig)
    hasCtypes=1

    # Can't have ctypes without python itself
    python_installed
    if [ $? -ne 0 ]; then
        return $hasCtypes
    fi

    # Attempt to run python with the single import command
    $PYTHON -c "import ctypes" > /dev/null 2>&1
    [ $? -eq 0 ] && hasCtypes=0

    return $hasCtypes
}

getInstalledVersion()
{
    # Parameter: Package to check if installed
    # Returns: Printable string (version installed or "None")
    if check_if_pkg_is_installed $1; then
        if [ "$INSTALLER" = "DPKG" ]; then
            local version="`dpkg -s $1 2> /dev/null | grep 'Version: '`"
            getVersionNumber "$version" "Version: "
        else
            # rpm based system can end up having multiple versions of a package.
            # return the latest version of the package installed
            local version=`rpm -q $1 | sort -V | tail -n 1 2> /dev/null`
            local num_installed=`rpm -q $1 | wc -l 2> /dev/null`
            if [ $num_installed -gt 1 ]; then
               echo "WARNING: Multiple versions of $1 seem to be installed." >&2
               echo "Please uninstall them. If the installer is run with --upgrade," >&2
               echo "the package with latest version will remain installed." >&2
            fi
            getVersionNumber $version ${1}-
        fi
    else
        echo "None"
    fi
}

shouldInstall_omsagent()
{
    local versionInstalled=`getInstalledVersion omsagent`
    [ "$versionInstalled" = "None" ] && return 0
    local versionAvailable=`getVersionNumber $OMS_PKG omsagent-`

    check_version_installable $versionInstalled $versionAvailable
}

shouldInstall_omsconfig()
{
    # Package omsconfig will never install without Python, Python ctypes, and curl ...
    if python_installed; then
        if python_ctypes_installed; then
            if check_if_program_exists_on_system curl; then
                local versionInstalled=`getInstalledVersion omsconfig`
                [ "$versionInstalled" = "None" ] && return 0
                local versionAvailable=`getVersionNumber $DSC_PKG omsconfig-`

                check_version_installable $versionInstalled $versionAvailable
            else
                return 1
            fi
        else
            return 1
        fi
    else
        return 1
    fi
}

shouldInstall_omi()
{
    local versionInstalled=`getInstalledVersion omi`
    [ "$versionInstalled" = "None" ] && return 0
    local versionAvailable=`getVersionNumber $OMI_PKG omi-`

    check_version_installable $versionInstalled $versionAvailable
}

shouldInstall_scx()
{
    local versionInstalled=`getInstalledVersion scx`
    [ "$versionInstalled" = "None" ] && return 0
    local versionAvailable=`getVersionNumber $SCX_PKG scx-`

    check_version_installable $versionInstalled $versionAvailable
}

remove_and_install()
{

    if [ -f /opt/microsoft/scx/bin/uninstall ]; then

        /opt/microsoft/scx/bin/uninstall R force
    else
        check_if_pkg_is_installed apache-cimprov
        if [ $? -eq 0 ]; then
            pkg_rm apache-cimprov
        fi

        check_if_pkg_is_installed mysql-cimprov
        if [ $? -eq 0 ]; then
            pkg_rm mysql-cimprov
        fi

        pkg_rm scx
        pkg_rm omi

    fi

    local temp_status=0

    pkg_add $OMI_PKG omi
    temp_status=$?

    if [ $temp_status -ne 0 ]; then
        echo "$OMI_PKG package failed to install and exited with status $temp_status"
        
        if [ $temp_status -eq 2 ]; then # dpkg is messed up
            return $DEPENDENCY_MISSING
        else
            return $OMI_INSTALL_FAILED
        fi        
    fi

    ${OMI_SERVICE} reload
    temp_status=$?

    if [ $temp_status -ne 0 ]; then
        if [ $temp_status -eq 2 ]; then
            ErrStr="System Issue with daemon control tool "
            ErrCode=$DEPENDENCY_MISSING
        elif [ $temp_status -eq 3 ]; then # dpkg is messed up
            ErrStr="omi server conf file missing"
            ErrCode=$DEPENDENCY_MISSING
        else
            ErrStr="OMI installation failed"
            ErrCode=$OMI_INSTALL_FAILED
        fi
        echo "OMI server failed to start due to $ErrStr and exited with status $temp_status"
        return $ErrCode
    fi

    if [ -f /usr/sbin/scxadmin ]; then
        rm -f /usr/sbin/scxadmin
    fi

    pkg_add $SCX_PKG scx
    temp_status=$?

    if [ $temp_status -ne 0 ]; then
        echo "$SCX_PKG package failed to install and exited with status $temp_status"
        return $SCX_INSTALL_FAILED
    fi

    return 0
}

install_extra_package()
{
    # Parameter: package name to install
    # Returns: 0 on success, 1 on failure
    if [ $# -ne 1 ]; then
        echo "INTERNAL ERROR: Incorrect number of parameters passed to install_extra_package" >&2
        cleanup_and_exit $INTERNAL_ERROR
    fi

    local install_cmd=""

    which zypper > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        install_cmd="zypper --non-interactive install"
    fi
    which yum > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        install_cmd="yum install -y"
    fi
    which apt-get > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        # Adding "--no-remove" flag to make APT fail when conflicting packages are detected.
        install_cmd="apt-get install -y --no-remove"
    fi

    if [ -z "$install_cmd" ]; then
        echo "No vendor found to install $1"
        return 1
    else
        $install_cmd $1
        return $?
    fi
}

#
# Main script follows
#

ulinux_detect_installer
set -e

while [ $# -ne 0 ]
do
    case "$1" in
        -d|--domain)
            topLevelDomain=$2
            shift 2
            ;;

        --extract-script)
            # hidden option, not part of usage
            # echo "  --extract-script FILE  extract the script to FILE."
            head -${SCRIPT_LEN} "${SCRIPT}" > "$2"
            shouldexit=true
            shift 2
            ;;

        --extract-binary)
            # hidden option, not part of usage
            # echo "  --extract-binary FILE  extract the binary to FILE."
            tail -n +${SCRIPT_LEN_PLUS_ONE} "${SCRIPT}" > "$2"
            shouldexit=true
            shift 2
            ;;

        --extract)
            verifyNoInstallationOption
            installMode=E
            shift 1
            ;;

        --force)
            forceFlag=true
            shift 1
            ;;

        --install)
            verifyNoInstallationOption
            verifyPrivileges "install"
            installMode=I
            shift 1
            ;;

        -p|--proxy)
            proxy=$2
            shift 2
            ;;

        --purge)
            verifyNoInstallationOption
            verifyPrivileges "purge"
            installMode=P
            shouldexit=true
            shift 1
            ;;

        --remove)
            verifyNoInstallationOption
            verifyPrivileges "remove"
            installMode=R
            shouldexit=true
            shift 1
            ;;

        --restart-deps)
            restartDependencies=--restart-deps
            shift 1
            ;;

        -s|--shared)
            onboardKey=$2
            shift 2
            ;;

        --source-references)
            source_references
            cleanup_and_exit 0
            ;;

        --version)
            echo "Version: `getVersionNumber $OMS_PKG omsagent-`"
            exit 0
            ;;

        --version-check)
            checkVersionAndCleanUp=true
            installMode=none
            shift 1
            ;;

        --upgrade)
            verifyNoInstallationOption
            verifyPrivileges "upgrade"
            installMode=U
            shift 1
            ;;

        -w|--id)
            onboardID=$2
            shift 2
            ;;

        --debug)
            echo "Starting shell debug mode." >&2
            echo "" >&2
            echo "SCRIPT_INDIRECT: $SCRIPT_INDIRECT" >&2
            echo "SCRIPT_DIR:      $SCRIPT_DIR" >&2
            echo "EXTRACT_DIR:     $EXTRACT_DIR" >&2
            echo "SCRIPT:          $SCRIPT" >&2
            echo >&2
            debugMode=true
            set -x
            shift 1
            ;;

        -a|--azure-resource)
            azureResourceID=$2
            shift 2
            ;;

        -m|--multi-homing-marker)
            multiHoming=$2
            shift 2
            ;;

        --enable-opsmgr)
            if [ ! -f /etc/scxagent-enable-port ]; then
                touch /etc/scxagent-enable-port
            fi
            shift 1
            ;;

        -\? | -h | --help)
            usage `basename $0` >&2
            cleanup_and_exit 0
            ;;

         *)
            echo "Unknown argument: '$1'" >&2
            echo "Use -h or --help for usage" >&2
            cleanup_and_exit $INVALID_OPTION_PROVIDED
            ;;
    esac
done

if [ -z "${installMode}" ]; then
    echo "$0: No options specified, specify --help for help" >&2
    cleanup_and_exit $NO_OPTION_PROVIDED
fi

ONBOARD_ERROR=0
[ -n "$topLevelDomain" ] && [ -z "$onboardID" -o -z "$onboardKey" ] && ONBOARD_ERROR=1
[ -z "$onboardID" -a -n "$onboardKey" ] && ONBOARD_ERROR=1
[ -n "$onboardID" -a -z "$onboardKey" ] && ONBOARD_ERROR=1

if [ "$ONBOARD_ERROR" -ne 0 ]; then
    echo "Must specify both workspace ID (--id) and key (--shared) to onboard" 1>& 2
    exit $INVALID_OPTION_PROVIDED
fi

if [ -n "$onboardID" -a -n "$onboardKey" ]; then
    verifyPrivileges "onboard"

    cat /dev/null > $ONBOARD_FILE
    chmod 600 $ONBOARD_FILE
    echo "WORKSPACE_ID=$onboardID" >> $ONBOARD_FILE
    echo "SHARED_KEY=$onboardKey" >> $ONBOARD_FILE

    if [ -n "$proxy" ]; then
        echo "PROXY=$proxy" >> $ONBOARD_FILE
    fi

    if [ -n "$topLevelDomain" ]; then
        echo "URL_TLD=$topLevelDomain" >> $ONBOARD_FILE
    fi

    if [ -n "$azureResourceID" ]; then
        echo "AZURE_RESOURCE_ID=$azureResourceID" >> $ONBOARD_FILE
    fi

    if [ -n "$multiHoming" ]; then
        echo "MULTI_HOMING_MARKER=$multiHoming" >> $ONBOARD_FILE
    fi

fi

#
# Note: From this point, we're in a temporary directory. This aids in cleanup
# from bundled packages in our package (we just remove the diretory when done).
#

mkdir -p $EXTRACT_DIR
cd $EXTRACT_DIR

# Do we need to remove the package?
set +e
if [ "$installMode" = "R" -o "$installMode" = "P" ]; then
    
    check_if_pkg_is_installed azsec-mdsd
    azsec_mdsd_installed=$?
    check_if_pkg_is_installed lad-mdsd
    lad_mdsd_installed=$?

    # if we detect LAD or AzSec while purging show a warning
    IS_MDSD_INSTALLED=$(( $azsec_mdsd_installed && $lad_mdsd_installed ))
    if [ $IS_MDSD_INSTALLED -eq 0 -a "$installMode" = "P" ]; then
        echo "---------- PURGE WARNING: lad-mdsd or azsec-mdsd was detected ----------"
        echo "Purging OMS may not fully succeed, because either LAD or AZSEC package has a dependency on OMS, SCX, and OMI."
        echo "To fix this issue you should remove LAD/AZSEC corresponding extension, check this documentation for more details"
        echo "about extension removal: https://docs.microsoft.com/en-us/cli/azure/vm/extension?view=azure-cli-latest#az-vm-extension-delete "
        echo "---------- PURGE WARNING ----------"
        # Should we force purge to exit with failure ?
        # cleanup_and_exit 1
    fi

    rm -f "$OMS_CONSISTENCY_INVOKER" > /dev/null 2>&1
    rm -f "$ONBOARD_FILE" > /dev/null 2>&1
    if [ -f /opt/microsoft/omsagent/bin/uninstall ]; then
        /opt/microsoft/omsagent/bin/uninstall $installMode
    else
        echo "---------- WARNING WARNING WARNING ----------"
        echo "Using new shell bundle to remove older kit."
        echo "Using fallback code to perform kit removal."
        echo "---------- WARNING WARNING WARNING ----------"
        echo

        # If bundled auoms is installed, then remove it
        check_if_pkg_is_installed auoms
        if [ $? -eq 0 ]; then
            pkg_rm auoms
        fi

        pkg_rm omsconfig

        
        # If MDSD/LAD is installed and we're just removing (not purging), leave OMS, SCX and OMI
        # if at least one of mdsd product is installed
        MDSD_INSTALLED=$(( $azsec_mdsd_installed && $lad_mdsd_installed ))

        # If LAD was installed don't remove omsagent, but proceed if purge mode was selected
        if [ $lad_mdsd_installed -ne 0 -o "$installMode" = "P" ]; then
            pkg_rm omsagent
        else
            echo "--- LAD detected; not removing OMS package ---"
            ws_conf_dir="/etc/opt/microsoft/omsagent/conf"
            primary_ws_id=''
            if [ -f ${ws_conf_dir}/omsadmin.conf ]; then
                primary_ws_id=`grep WORKSPACE_ID ${ws_conf_dir}/omsadmin.conf | cut -d= -f2`
            fi

            if [ "${primary_ws_id}" != "" -a "${primary_ws_id}" != "LAD" ]; then
                echo "--- Unboarding the workspace ${primary_ws_id}... ---"
                /opt/microsoft/omsagent/bin/omsadmin.sh -x ${primary_ws_id}
            fi
        fi

        if [ $MDSD_INSTALLED -ne 0 -o "$installMode" = "P" ]; then
            if [ -f /opt/microsoft/scx/bin/uninstall ]; then
                /opt/microsoft/scx/bin/uninstall $installMode
            else
                for i in /opt/microsoft/*-cimprov; do
                    PKG_NAME=`basename $i`
                    if [ "$PKG_NAME" != "*-cimprov" ]; then
                        echo "Removing ${PKG_NAME} ..."
                        pkg_rm ${PKG_NAME}
                    fi
                done

                # Now just simply pkg_rm scx and omi
                pkg_rm scx
                pkg_rm omi
            fi
        else
            echo "--- MDSD detected; not removing SCX or OMI packages ---"
        fi

        # If bundled auoms is installed, then remove it
        check_if_pkg_is_installed auoms
        if [ $? -eq 0 ]; then
            pkg_rm auoms
        fi

        if [ "$installMode" = "P" ]; then
            echo "Purging all files in cross-platform agent ..."

            #
            # Be careful to not remove files if dependent packages are still using them
            #

            check_if_pkg_is_installed omsconfig
            if [ $? -ne 0 ]; then
                rm -rf /etc/opt/microsoft/omsconfig /opt/microsoft/omsconfig /var/opt/microsoft/omsconfig
            fi

            check_if_pkg_is_installed omsagent
            if [ $? -ne 0 ]; then
                rm -rf /etc/opt/microsoft/omsagent /opt/microsoft/omsagent /var/opt/microsoft/omsagent
            fi

            check_if_pkg_is_installed scx
            if [ $? -ne 0 ]; then
                rm -rf /etc/opt/microsoft/scx /opt/microsoft/scx /var/opt/microsoft/scx \
                    /etc/opt/microsoft/*-cimprov /opt/microsoft/*-cimprov /var/opt/microsoft/*-cimprov
            fi

            check_if_pkg_is_installed omi
            if [ $? -ne 0 ]; then
                rm -rf /etc/opt/omi /opt/omi /var/opt/omi
            fi

            check_if_pkg_is_installed auoms
            if [ $? -ne 0 ]; then
                rm -rf /etc/opt/microsoft/auoms /opt/microsoft/auoms /var/opt/microsoft/auoms
            fi

            rmdir /etc/opt/microsoft /opt/microsoft /var/opt/microsoft > /dev/null 2>&1 || true
            rmdir /etc/opt /var/opt > /dev/null 2>&1 || true
        fi
    fi
    rm -f /etc/collectd.d/oms.conf > /dev/null 2>&1
    rm -f /etc/collectd/collectd.conf.d/oms.conf > /dev/null 2>&1
fi

if [ -n "${shouldexit}" ]
then
    # when extracting script/tarball don't also install
    cleanup_and_exit 0
fi

#
# Do stuff before extracting the binary here, for example test [ `id -u` -eq 0 ],
# validate space, platform, uninstall a previous version, backup config data, etc...
#

# Pre-flight if omsconfig installation will fail ...

if [ "$installMode" = "I" -o "$installMode" = "U" ]; then
    compare_install_type
    compare_arch

    python_installed
    if [ $? -ne 0 ]; then
        if [ -z "${forceFlag}" ]; then
            echo "Error: Python is not installed on this system, installation cannot continue." >&2
            echo "Please install either the python2 or python3 package." >&2
            echo "You can run this shell bundle with --force; in this case, we will install omsagent," >&2
            echo "but omsconfig (DSC configuration) will not be available and will need to be re-installed." >&2
            cleanup_and_exit $INSTALL_PYTHON
        else
            echo "Python is not installed on this system, please install either the python2 or python3 package and re-install omsconfig later."
            echo "Installation will continue without installing omsconfig."
        fi
    fi

    python_ctypes_installed
    if [ $? -ne 0 ]; then
        if [ -z "${forceFlag}" ]; then
            echo "Error: Python is not configured or Python does not support ctypes on this system, installation cannot continue." >&2
            echo "Please install the ctypes package (python-ctypes)or upgrade Python to a newer version of python that comes with the ctypes module." >&2
            echo "You can check if the ctypes module is installed by starting python and running the command: 'import ctypes'." >&2
            echo "You can run this shell bundle with --force; in this case, we will install omsagent," >&2
            echo "but omsconfig (DSC configuration) will not be available and will need to be re-installed." >&2
            cleanup_and_exit $INSTALL_PYTHON_CTYPES
        else
            echo "Python is not configured or it does not support ctypes on this system, please upgrade Python to a newer version that comes with the ctypes module and re-install omsconfig later."
            echo "Installation will continue without installing omsconfig."
        fi
    fi

    install_if_program_does_not_exist_on_system tar
    if [ $? -ne 0 ]; then
        echo "tar was not installed, installation cannot continue. Please install tar."
        cleanup_and_exit $INSTALL_TAR
    fi

    install_if_program_does_not_exist_on_system sed
    if [ $? -ne 0 ]; then
        echo "sed was not installed, installation cannot continue. Please install sed."
        cleanup_and_exit $INSTALL_SED
    fi

    install_if_program_does_not_exist_on_system curl
    if [ $? -ne 0 ]; then
        if [ -z "${forceFlag}" ]; then
            echo "Error: curl was not installed, installation cannot continue."
            echo "You can run this shell bundle with --force; in this case, we will install omsagent,"
            echo "but omsconfig (DSC configuration) will not be available and will need to be re-installed."
            cleanup_and_exit $INSTALL_CURL
        else
            echo "curl was not installed, please install curl and re-install omsconfig (DSC configuration) later."
            echo "Installation will continue without installing omsconfig."
        fi
    fi

    check_if_program_exists_on_system gpg
    if [ $? -ne 0 ]; then
        echo "gpg is not installed, installation cannot continue."
        cleanup_and_exit $INSTALL_GPG
    fi
fi

#
# Extract the binary here.
#

echo "Extracting..."

tail -n +${SCRIPT_LEN_PLUS_ONE} "${SCRIPT}" | tar xzf -
STATUS=$?
if [ ${STATUS} -eq 127 ]
then
    echo "Failed: could not extract the install bundle. Exit code: 127"
    echo "Please make sure that tar is installed."
    cleanup_and_exit $INSTALL_TAR
elif [ ${STATUS} -ne 0 ]
then
    echo "Failed: could not extract the install bundle."
    cleanup_and_exit ${STATUS}
fi

if [ -n "${checkVersionAndCleanUp}" ]; then

    # OMS agent itself
    versionInstalled=`getInstalledVersion omsagent`
    versionAvailable=`getVersionNumber $OMS_PKG omsagent-`
    if shouldInstall_omsagent; then shouldInstall="Yes"; else shouldInstall="No"; fi
    printf '%-15s%-15s%-15s%-15s\n' omsagent $versionInstalled $versionAvailable $shouldInstall

    # omsconfig
    versionInstalled=`getInstalledVersion omsconfig`
    versionAvailable=`getVersionNumber $DSC_PKG omsconfig-`
    if shouldInstall_omsconfig; then shouldInstall="Yes"; else shouldInstall="No"; fi
    printf '%-15s%-15s%-15s%-15s\n' omsconfig $versionInstalled $versionAvailable "$shouldInstall"

    # OMI package
    versionInstalled=`getInstalledVersion omi`
    versionAvailable=`getVersionNumber $OMI_PKG omi-`
    if shouldInstall_omi; then shouldInstall="Yes"; else shouldInstall="No"; fi
    printf '%-15s%-15s%-15s%-15s\n' omi $versionInstalled $versionAvailable $shouldInstall

    # SCX package
    versionInstalled=`getInstalledVersion scx`
    versionAvailable=`getVersionNumber $SCX_PKG scx-`
    if shouldInstall_scx; then shouldInstall="Yes"; else shouldInstall="No"; fi
    printf '%-15s%-15s%-15s%-15s\n' scx $versionInstalled $versionAvailable $shouldInstall

    # Apache provider
    if [ -f ./oss-kits/apache-cimprov-*.sh ]; then
        ./oss-kits/apache-cimprov-*.sh --version-check | tail -1
    fi

    # MySQL provider
    if [ -f ./oss-kits/mysql-cimprov-*.sh ]; then
        ./oss-kits/mysql-cimprov-*.sh --version-check | tail -1
    fi

    # Docker provider
    if [ -f ./oss-kits/docker-cimprov-*.sh ]; then
        ./oss-kits/docker-cimprov-*.sh --version-check | tail -1
    fi

    cleanup_and_exit 0
fi

#
# Do stuff after extracting the binary here, such as actually installing the package.
#

KIT_STATUS=0
BUNDLE_EXIT_STATUS=0
OMI_EXIT_STATUS=0
SCX_EXIT_STATUS=0

# Now do our installation work (or just exit)

case "$installMode" in
    E)
        # Files are extracted, so just exit
        cleanup_and_exit 0 "SAVE"
        ;;

    I)
        INSTALL_TST="yes" # set variable to install tst upon exit

        check_if_pkg_is_installed scx
        scx_installed=$?
        check_if_pkg_is_installed omi
        omi_installed=$?

        if [ $scx_installed -ne 0 -a $omi_installed -ne 0 ]; then

            # Install OMI
            shouldInstall_omi
            if [ $? -eq 0 ]; then
                pkg_add ${OMI_PKG} omi
                OMI_EXIT_STATUS=$?
            fi

            ${OMI_SERVICE} reload
            temp_status=$?

            if [ $temp_status -ne 0 ]; then
                if [ $temp_status -eq 2 ]; then
                    ErrStr="System Issue with daemon control tool "
                    ErrCode=$DEPENDENCY_MISSING
                elif [ $temp_status -eq 3 ]; then # dpkg is messed up
                    ErrStr="omi server conf file missing"
                    ErrCode=$DEPENDENCY_MISSING
                else
                    ErrStr="OMI installation failed"
                    ErrCode=$OMI_INSTALL_FAILED
                fi

                echo "OMI server failed to start due to $ErrStr and exited with status $temp_status"
                OMI_EXIT_STATUS=$ErrCode
             fi


            # Install SCX
            shouldInstall_scx
            if [ $? -eq 0 ]; then

                if [ -f /usr/sbin/scxadmin ]; then
                    rm -f /usr/sbin/scxadmin
                fi

                pkg_add ${SCX_PKG} scx
                SCX_EXIT_STATUS=$?
            fi

            # Try to re-install if any of OMI or SCX install failed
            if [ "${OMI_EXIT_STATUS}" -ne 0 -o "${SCX_EXIT_STATUS}" -ne 0 ]; then
                remove_and_install
                TEMP_STATUS=$?
                if [ $TEMP_STATUS -ne 0 ]; then
                    echo "Install failed"
                    cleanup_and_exit $TEMP_STATUS
                fi
            fi

            # Install OMS Agent
            pkg_add ${OMS_PKG} omsagent
            TEMP_STATUS=$?
            if [ $TEMP_STATUS -ne 0 ]; then
               echo "$OMS_PKG package failed to install and exited with status $TEMP_STATUS"
               cleanup_and_exit $OMS_INSTALL_FAILED
            fi

            disable_jemalloc_if_cylance_exist

            # Install DSC
            if shouldInstall_omsconfig; then
                pkg_add ${DSC_PKG} omsconfig
                TEMP_STATUS=$?
                if [ $TEMP_STATUS -ne 0 ]; then
                    echo "$DSC_PKG package failed to install and exited with status $TEMP_STATUS"
                    cleanup_and_exit $DSC_INSTALL_FAILED
                fi
            fi

            # Install bundled providers
            [ -n "${forceFlag}" ] && FORCE="--force" || FORCE=""
            echo "----- Installing bundled packages -----"
            for i in oss-kits/*-oss-test.sh; do
                # If filespec didn't expand, break out of loop
                [ ! -f $i ] && break

                # It's possible we have a test file without a kit; if so, ignore it
                OSS_BUNDLE=`basename $i -oss-test.sh`
                [ ! -f oss-kits/${OSS_BUNDLE}-cimprov-*.sh ] && continue

                ./$i
                if [ $? -eq 0 ]; then
                    ./oss-kits/${OSS_BUNDLE}-cimprov-*.sh --install $FORCE $restartDependencies
                    TEMP_STATUS=$?
                    if [ $TEMP_STATUS -ne 0 ]; then
                        echo "$OSS_BUNDLE provider package failed to install and exited with status $TEMP_STATUS"
                        BUNDLE_EXIT_STATUS=$SCX_KITS_INSTALL_FAILED
                    fi
                fi
            done

            # Handling auoms 1.x vs 2.x installation
            is_suse11_platform_with_openssl1
            if [ $? -eq 0 ];then
               BUNDLES_PATH=$BUNDLES_LEGACY_PATH
            fi
            for i in ${BUNDLES_PATH}/*-bundle-test.sh; do
                # If filespec didn't expand, break out of loop
                [ ! -f $i ] && break

                # It's possible we have a test file without bundle; if so, ignore it
                BUNDLE=`basename $i -bundle-test.sh`
                [ ! -f ${BUNDLES_PATH}/${BUNDLE}-*universal.*.sh ] && continue

                ./$i
                if [ $? -eq 0 ]; then
                    ./${BUNDLES_PATH}/${BUNDLE}-*universal.*.sh --install $FORCE $restartDependencies
                    TEMP_STATUS=$?
                    if [ $TEMP_STATUS -ne 0 ]; then
                        echo "$BUNDLE package failed to install and exited with status $TEMP_STATUS"
                        BUNDLE_EXIT_STATUS=$BUNDLED_INSTALL_FAILED
                    fi
                fi
            done
        else
            echo "The omi or scx package is already installed. Please run the" >&2
            echo "installer with --upgrade (instead of --install) to continue." >&2
            KIT_STATUS=$USE_UPGRADE
        fi
        ;;

    U)
        INSTALL_TST="yes" # set variable to install tst upon exit

        # Install OMI
        shouldInstall_omi
        pkg_upd ${OMI_PKG} omi $?
        OMI_EXIT_STATUS=$?
        ${OMI_SERVICE} reload
        temp_status=$?

        if [ $temp_status -ne 0 ]; then
            if [ $temp_status -eq 2 ]; then
                ErrStr="System Issue with daemon control tool "
                ErrCode=$DEPENDENCY_MISSING
            elif [ $temp_status -eq 3 ]; then # dpkg is messed up
                  ErrStr="omi server conf file missing"
                  ErrCode=$DEPENDENCY_MISSING
            else
                  ErrStr="OMI installation failed"
                  ErrCode=$OMI_INSTALL_FAILED
            fi

            echo "OMI server failed to start due to $ErrStr and exited with status $temp_status"
            OMI_EXIT_STATUS=$ErrCode
        fi
	
        # Install SCX
        shouldInstall_scx
        if [ $? -eq 0 ]; then

            if [ -f /usr/sbin/scxadmin ]; then
                rm -f /usr/sbin/scxadmin
            fi

            pkg_upd $SCX_PKG scx $?
            SCX_EXIT_STATUS=$?
        fi

        # Try to re-update if any of OMI or SCX update failed
        if [ "${OMI_EXIT_STATUS}" -ne 0 -o "${SCX_EXIT_STATUS}" -ne 0 ]; then

            remove_and_install
            TEMP_STATUS=$?
            if [ $TEMP_STATUS -ne 0 ]; then
                echo "Upgrade failed"
                cleanup_and_exit $TEMP_STATUS
            fi
        fi

        # Update OMS Agent
        shouldInstall_omsagent
        rm -f "$OMS_CONSISTENCY_INVOKER" > /dev/null 2>&1
        pkg_upd $OMS_PKG omsagent $?
        TEMP_STATUS=$?
        if [ $TEMP_STATUS -ne 0 ]; then
            echo "$OMS_PKG package failed to upgrade and exited with status $TEMP_STATUS"
            cleanup_and_exit $OMS_INSTALL_FAILED
        fi

        disable_jemalloc_if_cylance_exist

        # Hotfix TCP fix: seems during an upgrade configs will not be updated all the time
        # this is hotfix to revert back TCP change introduced previously
        echo "Applying Syslog conf hotfix..."
        if [ -f /etc/opt/microsoft/omsagent/conf/omsagent.d/syslog.conf ]; then
            sed -i "s/tcp/udp/g" /etc/opt/microsoft/omsagent/conf/omsagent.d/syslog.conf
        else
            echo "Syslog conf (/etc/opt/microsoft/omsagent/conf/omsagent.d/syslog.conf) not found, hotfix skipped."
        fi

        # Update DSC
        shouldInstall_omsconfig
        pkg_upd $DSC_PKG omsconfig $?
        TEMP_STATUS=$?
        if [ $TEMP_STATUS -ne 0 ]; then
            echo "$DSC_PKG package failed to upgrade and exited with status $TEMP_STATUS"
            cleanup_and_exit $DSC_INSTALL_FAILED
        fi

        # Hotfix DSC bug for nxOMSPlugin: removing 15 files that were not cleaned up by DSC
        echo "Applying DSC nxOMSSyslog hotfix..."
        rm -f /opt/microsoft/omsconfig/modules/nxOMSSudoCustomLog/DSCResources/MSFT_nxOMSSudoCustomLogResource/CustomLog/Plugin/in_sudo_tail.rb
        rm -f /opt/microsoft/omsconfig/modules/nxOMSSudoCustomLog/DSCResources/MSFT_nxOMSSudoCustomLogResource/CustomLog/Plugin/tailfilereader.rb
        rm -f /opt/microsoft/omsconfig/modules/nxOMSPlugin/DSCResources/MSFT_nxOMSPluginResource/Plugins/Common/plugin/agent_common.rb
        rm -f /opt/microsoft/omsconfig/modules/nxOMSPlugin/DSCResources/MSFT_nxOMSPluginResource/Plugins/Common/plugin/agent_telemetry_script.rb
        rm -f /opt/microsoft/omsconfig/modules/nxOMSPlugin/DSCResources/MSFT_nxOMSPluginResource/Plugins/Common/plugin/blocklock.rb
        rm -f /opt/microsoft/omsconfig/modules/nxOMSPlugin/DSCResources/MSFT_nxOMSPluginResource/Plugins/Common/plugin/heartbeat_lib.rb
        rm -f /opt/microsoft/omsconfig/modules/nxOMSPlugin/DSCResources/MSFT_nxOMSPluginResource/Plugins/Common/plugin/in_agent_telemetry.rb
        rm -f /opt/microsoft/omsconfig/modules/nxOMSPlugin/DSCResources/MSFT_nxOMSPluginResource/Plugins/Common/plugin/in_oms_omi.rb
        rm -f /opt/microsoft/omsconfig/modules/nxOMSPlugin/DSCResources/MSFT_nxOMSPluginResource/Plugins/Common/plugin/oms_common.rb
        rm -f /opt/microsoft/omsconfig/modules/nxOMSPlugin/DSCResources/MSFT_nxOMSPluginResource/Plugins/Common/plugin/oms_configuration.rb
        rm -f /opt/microsoft/omsconfig/modules/nxOMSPlugin/DSCResources/MSFT_nxOMSPluginResource/Plugins/Common/plugin/oms_diag_lib.rb
        rm -f /opt/microsoft/omsconfig/modules/nxOMSPlugin/DSCResources/MSFT_nxOMSPluginResource/Plugins/Common/plugin/oms_omi_lib.rb
        rm -f /opt/microsoft/omsconfig/modules/nxOMSPlugin/DSCResources/MSFT_nxOMSPluginResource/Plugins/Common/plugin/out_oms.rb
        rm -f /opt/microsoft/omsconfig/modules/nxOMSPlugin/DSCResources/MSFT_nxOMSPluginResource/Plugins/Common/plugin/out_oms_blob.rb
        rm -f /opt/microsoft/omsconfig/modules/nxOMSPlugin/DSCResources/MSFT_nxOMSPluginResource/Plugins/Common/plugin/out_oms_diag.rb

        if [ $KIT_STATUS -eq 0 ]; then
            # Remove fluentd conf for OMSConsistencyInvoker upon upgrade, if it exists
            rm -f /etc/opt/microsoft/omsagent/conf/omsagent.d/omsconfig.consistencyinvoker.conf

            # In case --upgrade is run without -w <id> and -s <key>
            if [ ! -f "$OMS_CONSISTENCY_INVOKER" ]; then
                randomNo=$(od -An -N1 -i /dev/urandom)
                A=$(($randomNo%13+2))
                B=$(($A+15))
                C=$(($B+15))
                D=$(($C+15))
                echo "$A,$B,$C,$D * * * * omsagent /opt/omi/bin/OMSConsistencyInvoker >/dev/null 2>&1" > $OMS_CONSISTENCY_INVOKER		
            fi
            /opt/omi/bin/service_control restart
        fi

        # Upgrade bundled providers
        [ -n "${forceFlag}" ] && FORCE="--force" || FORCE=""
        echo "----- Updating bundled packages -----"
        for i in oss-kits/*-oss-test.sh; do
            # If filespec didn't expand, break out of loop
            [ ! -f $i ] && break

            # It's possible we have a test file without a kit; if so, ignore it
            OSS_BUNDLE=`basename $i -oss-test.sh`
            [ ! -f oss-kits/${OSS_BUNDLE}-cimprov-*.sh ] && continue

            ./$i
            if [ $? -eq 0 ]; then
                ./oss-kits/${OSS_BUNDLE}-cimprov-*.sh --upgrade $FORCE $restartDependencies
                TEMP_STATUS=$?
                if [ $TEMP_STATUS -ne 0 ]; then
                    echo "$OSS_BUNDLE provider package failed to upgrade and exited with status $TEMP_STATUS"
                    BUNDLE_EXIT_STATUS=$SCX_KITS_INSTALL_FAILED
                fi
            fi
        done

        # Handling auoms 1.x vs 2.x installation
        is_suse11_platform_with_openssl1
        if [ $? -eq 0 ];then
           BUNDLES_PATH=$BUNDLES_LEGACY_PATH
        fi
        for i in ${BUNDLES_PATH}/*-bundle-test.sh; do
            # If filespec didn't expand, break out of loop
            [ ! -f $i ] && break

            # It's possible we have a test file without bundle; if so, ignore it
            BUNDLE=`basename $i -bundle-test.sh`
            [ ! -f ${BUNDLES_PATH}/${BUNDLE}-*universal.*.sh ] && continue

            ./$i
            if [ $? -eq 0 ]; then
                ./${BUNDLES_PATH}/${BUNDLE}-*universal.*.sh --upgrade $FORCE $restartDependencies
                TEMP_STATUS=$?
                if [ $TEMP_STATUS -ne 0 ]; then
                    echo "$BUNDLE package failed to upgrade and exited with status $TEMP_STATUS"
                    BUNDLE_EXIT_STATUS=$BUNDLED_INSTALL_FAILED
                fi
            fi
        done
        ;;

    *)
        echo "$0: Invalid setting of variable \$installMode, exiting" >&2
        cleanup_and_exit $INTERNAL_ERROR
esac

# Remove temporary files (now part of cleanup_and_exit) and exit

if [ "$KIT_STATUS" -ne 0 ]; then
    cleanup_and_exit ${KIT_STATUS}
elif [ "$BUNDLE_EXIT_STATUS" -ne 0 ]; then
    cleanup_and_exit ${BUNDLE_EXIT_STATUS}
else
    cleanup_and_exit 0
fi

#####>>- This must be the last line of this script, followed by a single empty line. -<<#####
