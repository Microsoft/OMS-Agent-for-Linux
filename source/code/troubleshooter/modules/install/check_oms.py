import re

from error_codes          import *
from errors               import error_info, is_error, get_input, print_errors
from helpers              import geninfo_lookup, get_curr_oms_version, update_omsadmin
from .check_pkgs          import get_package_version
from connect.check_endpts import check_internet_connect

OMSAGENT_URL = "https://raw.github.com/microsoft/OMS-Agent-for-Linux/master/docs/OMS-Agent-for-Linux.md"



# get current OMS version running on machine
def get_oms_version():
    version = get_package_version('omsagent')
    # couldn't find OMSAgent
    if (version == None):
        return None
    return version



# compare two versions, see if the first is newer than / the same as the second
def comp_versions_ge(v1, v2):
    # split on '.' and '-'
    v1_split = v1.split('.|-')
    v2_split = v2.split('.|-')
    # get rid of trailing zeroes (e.g. 1.12.0 is the same as 1.12)
    while (v1_split[-1] == '0'):
        v1_split = v1_split[:-1]
    while (v2_split[-1] == '0'):
        v2_split = v2_split[:-1]
    # iterate through version elements
    for (v1_elt, v2_elt) in (zip(v1_split, v2_split)):
        # curr version elements are same
        if (v1_elt == v2_elt):
            continue
        try:
            # parse as integers
            return (int(v1_elt) >= int(v2_elt))
        except:
            # contains wild card characters
            if ((v1_elt in ['x','X','*']) or (v2_elt in ['x','X','*'])):
                return True
            # remove non-numeric characters, try again
            v1_nums = [int(n) for n in re.findall('\d+', v1_elt)]
            v2_nums = [int(n) for n in re.findall('\d+', v2_elt)]
            return all([(i>=j) for i,j in zip(v1_nums, v2_nums)])
    # check if subversion is newer (e.g. 1.11.3 to 1.11)
    return (len(v1_split) >= len(v2_split))
    
def ask_update_old_version(oms_version, curr_oms_version, cpu_bits):
    print("--------------------------------------------------------------------------------")
    print("You are currently running OMS Verion {0}. There is a newer version\n"\
          "available which may fix your issue (version {1}).".format(oms_version, curr_oms_version))
    answer = get_input("Do you want to update? (y/n)", (lambda x : x.lower() in ['y','yes','n','no']),\
                       "Please type either 'y'/'yes' or 'n'/'no' to proceed.")
    # user does want to update
    if (answer.lower() in ['y', 'yes']):
        print("--------------------------------------------------------------------------------")
        print("Please head to the Github link below and click on 'Download Latest OMS Agent\n"\
              "for Linux ({0})' in order to update to the newest version:".format(cpu_bits))
        print("\n    https://github.com/microsoft/OMS-Agent-for-Linux\n")
        print("And follow the instructions given here:")
        print("\n    https://github.com/microsoft/OMS-Agent-for-Linux/blob/master/docs/"\
                "OMS-Agent-for-Linux.md#upgrade-from-a-previous-release\n")
        return USER_EXIT
    # user doesn't want to update
    elif (answer.lower() in ['n', 'no']):
        print("Continuing on with troubleshooter...")
        print("--------------------------------------------------------------------------------")
        return NO_ERROR



def check_oms(interactive):
    cpu_bits = geninfo_lookup('CPU_BITS')

    oms_version = get_oms_version()
    if (oms_version == None):
        return ERR_OMS_INSTALL

    # check if version is >= 1.11
    if (not comp_versions_ge(oms_version, '1.11')):
        error_info.append((oms_version, cpu_bits))
        return ERR_OLD_OMS_VER

    # get most recent version
    (curr_oms_version, e) = get_curr_oms_version(OMSAGENT_URL)

    # getting current version failed
    if (curr_oms_version == None):
        # could connect, just formatting issue
        if (e == None):
            return ERR_GETTING_OMS_VER
        # couldn't connect
        else:
            checked_internet = check_internet_connect()
            # issue with connecting to Github specifically
            if (checked_internet == NO_ERROR):
                print("WARNING: can't connect to {0}: {1}\n Skipping this check...".format(OMSAGENT_URL, e))
                print("--------------------------------------------------------------------------------")
            # issue with general internet connectivity
            else:
                return checked_internet

    # got current version
    else:
        # if not most recent version, ask if want to update
        if (interactive and (not comp_versions_ge(oms_version, curr_oms_version))):
            if (ask_update_old_version(oms_version, curr_oms_version, cpu_bits) == USER_EXIT):
                return USER_EXIT

    return update_omsadmin()