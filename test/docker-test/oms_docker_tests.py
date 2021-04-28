"""
Test the OMS Agent on all or a subset of images.

Setup: read parameters and setup HTML report
Test:
1. Create container and install agent
2. Wait for data to propagate to backend and check for data
?. Repeat steps 1 and 2 with newer agent
4. De-onboard and re-onboard agent
5. Remove agent
6. Reinstall agent
?. Optionally, wait for hours and check data and agent status
7. Purge agent and delete container
Finish: compile HTML report and log file
"""

import argparse
import atexit
import enum
import json
import os
import subprocess
import re
import shutil
import sys
from collections import OrderedDict
from datetime import datetime, timedelta
from glob import glob
from time import sleep

from json2html import *
from verify_e2e import check_e2e

E2E_DELAY = 10 # Delay (minutes) before checking for data
SUCCESS_TEMPLATE = "<td><span style='background-color: #66ff99'>{0}</span></td>"
FAILURE_TEMPLATE = "<td><span style='background-color: red; color: white'>{0}</span></td>"

class WorkspaceStatus(enum.Enum):
    ONBOARDED = 1
    NOT_ONBOARDED = 2
    ERROR = 3

class Color:
    BOLD = '\033[1m'
    RED = '\033[91m'
    ENDC = '\033[0m'

images = ["ubuntu14", "ubuntu16", "ubuntu18", "ubuntu20py3", "debian8", "debian9", "debian10", "centos6", "centos7", "centos8py3", "oracle6", "oracle7", "redhat6", "redhat7", "redhat8py3"]
# images = ["ubuntu14", "ubuntu16", "ubuntu18", "ubuntu20", "debian8", "debian9", "debian10", "centos6", "centos7", "centos8", "oracle6", "oracle7", "redhat6", "redhat7", "redhat8"]
python3_images = ["ubuntu20py3", "redhat8py3", "centos8py3"]
hostnames = []
install_times = {}
procs = {}

example_text = """examples:
  $ python -u oms_docker_tests.py\t\t\tall images
  $ python -u oms_docker_tests.py -i -p\t\t\tall images, in parallel, with instant upgrade
  $ python -u oms_docker_tests.py -p -l 120\t\tall images, in parallel, long mode with length specified
  $ python -u oms_docker_tests.py -d image1 image2 ...\tsubset of images
"""

parser = argparse.ArgumentParser(epilog=example_text, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument('-p', '--parallel', action='store_true', help='test distros in parallel')
parser.add_argument('-i', '--instantupgrade', action='store_true', help='test upgrade on top of old bundle')
parser.add_argument('-l', '--long', nargs='?', type=int, const=250, default=0, help='add a long wait in minutes followed by a second verification (default: 250)')
parser.add_argument('-d', '--distros', nargs='*', default=images, help='list of distros to test (default: all)')
args = parser.parse_args()
images =  [i for i in args.distros if i in images]
invalid = [i for i in args.distros if i not in images]

if invalid:
    print('invalid distro(s): {0}. continuing ...'.format(invalid))

with open('{0}/parameters.json'.format(os.getcwd()), 'r') as f:
    parameters = f.read()
    if re.search(r'"<.*>"', parameters):
        print('Please replace placeholders in parameters.json')
        exit()
    parameters = json.loads(parameters)

try:
    if parameters['oms bundle'] and os.path.isfile('omsfiles/'+parameters['oms bundle']):
        oms_bundle = parameters['oms bundle']

    if parameters['old oms bundle'] and os.path.isfile('omsfiles/'+parameters['old oms bundle']):
        old_oms_bundle = parameters['old oms bundle']

except KeyError:
    print('parameters not defined correctly or omsbundle file not found')

workspace_id = parameters['workspace id']
workspace_key = parameters['workspace key']

def append_file(src, dest):
    """Append contents of src to dest."""
    f = open(src, 'r')
    dest.write(f.read())
    f.close()

def copy_append_remove(container, image, src, dest):
    """Copy file from docker container, append it to the specified destination, and delete it"""
    os.system("docker cp {0}:/home/temp/{1} results/{2}/".format(container, src, image))
    append_file('results/{0}/{1}'.format(image, src), dest)
    os.remove('results/{0}/{1}'.format(image, src))

def write_log_command(cmd, log):
    """Print cmd to stdout and append it to log file."""
    print(Color.BOLD + cmd + Color.ENDC)
    log.write(cmd + '\n')
    log.write('-' * 40)
    log.write('\n')

def get_time_diff(timevalue1, timevalue2):
    """Get time difference in minutes and seconds"""
    timediff = timevalue2 - timevalue1
    minutes, seconds = divmod(timediff.days * 86400 + timediff.seconds, 60)
    return minutes, seconds

def setup_vars(image):
    """Set up variables and open necessary log files for a generalized test operation."""
    container = image + '-container'
    log_path = 'results/{0}/result.log'.format(image)
    html_path = 'results/{0}/result.html'.format(image)
    omslog_path = 'results/{0}/omsagent.log'.format(image)
    tmp_path = 'results/{0}/temp.log'.format(image)
    log_file = open(log_path, 'a+')
    html_file = open(html_path, 'a+')
    oms_file = open(omslog_path, 'a+')
    return container, log_path, html_path, omslog_path, tmp_path, log_file, html_file, oms_file

def close_files(*args):
    for f in args:
        f.close()

def get_versioned_python(image):
    if image in python3_images:
        return "python3"
    else:
        return "python2"

def check_workspace_status(container):
    """Check the onboarding status of the agent using omsadmin.sh."""
    try:
        out = subprocess.check_output('docker exec {0} /opt/microsoft/omsagent/bin/omsadmin.sh -l'.format(container), shell=True)
    except subprocess.CalledProcessError as e:
        return WorkspaceStatus.ERROR

    if re.search('[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', out).group(0) == workspace_id:
        return WorkspaceStatus.ONBOARDED
    elif out.rstrip() == "No Workspace":
        return WorkspaceStatus.NOT_ONBOARDED
    else:
        return WorkspaceStatus.ERROR

# TODO this should be elsewhere/def'd
for image in images:
    path = 'results/{0}'.format(image)
    if not os.path.isdir('results/{0}'.format(image)):
        os.mkdir(path)

subfolder = '{}/'.format(images[0]) if len(images) == 1 or args.parallel else ''
result_html_file = open('results/{0}finalresult.html'.format(subfolder), 'a+')
result_log_file = open('results/{0}finalresult.log'.format(subfolder), 'a+')

htmlstart = """<!DOCTYPE html>
<html>
<head>
<style>
table {
    font-family: arial, sans-serif;
    border-collapse: collapse;
    width: 100%;
}

td, th {
    border: 1px solid #dddddd;
    text-align: left;
    padding: 8px;
}

tr:nth-child(even) {
    background-color: #dddddd;
}
</style>
</head>
<body>
"""
result_html_file.write(htmlstart)

def main():
    """Orchestrate fundemental testing steps onlined in header docstring."""

    if args.parallel:
        print('Running tests in parallel. Progress will be hidden. Final report will generated for each distro individually')
        for image in images:
            flags = ' '.join([a for a in sys.argv[1:] if a not in images and a not in ['-p', '--parallel', '-d', '--distros']])
            cmd = 'python -u {0} {1} -d {2}'.format(sys.argv[0], flags, image).split()
            print(cmd)
            with open(os.devnull, 'wb') as devnull:
                procs[image] = subprocess.Popen(cmd, stdout=devnull, stderr=devnull, env={'SUBPROCESS': 'true'})
        done = False
        elapsed_time = 0
        while not done:
            status = []
            status_msg = '\rStatus after {0} minutes ['.format(elapsed_time)
            for p in procs.items():
                status.append(p[1].poll())
                status_code = 'running' if status[-1] is None else (Color.RED + status[-1] + Color.ENDC if status[-1] else 'done')
                status_msg += ' {0}: {1},'.format(p[0], status_code)
            sys.stdout.write(status_msg[:-1] + ' ]')
            sys.stdout.flush()
            done = True if None not in status else False
            sleep(60)
            elapsed_time += 1
        print('\nFinished!')
    else:
        if args.instantupgrade:
            if not old_oms_bundle:
                print('Instant upgrade specified but no old oms bundle provided. Check parameters.json and omsfiles directory for bundle file existence')
                sys.exit(0)
            install_msg = install_agent(old_oms_bundle)
            verify_msg = verify_data()
            instantupgrade_install_msg = upgrade_agent(oms_bundle)
            instantupgrade_verify_msg = verify_data()
            deonboard_reonboard_msg = deonboard_reonboard()
        else:
            install_msg = install_agent(oms_bundle)
            verify_msg = verify_data()
            deonboard_reonboard_msg = deonboard_reonboard()
            instantupgrade_install_msg, instantupgrade_verify_msg = None, None

        remove_msg = remove_agent()
        reinstall_msg = reinstall_agent()
        if args.long:
            for i in reversed(range(1, args.long + 1)):
                sys.stdout.write('\rLong-term delay: T-{0} minutes...'.format(i))
                sys.stdout.flush()
                sleep(60)
            print('')
            install_times.clear()
            for image in images:
                install_times.update({image: datetime.now()})
                container = image + '-container'
                inject_logs(container, image)
            long_verify_msg = verify_data()
            long_status_msg = check_status()
        else:
            long_verify_msg, long_status_msg = None, None
        purge_delete_agent()
        messages = (install_msg, verify_msg, instantupgrade_install_msg, instantupgrade_verify_msg, deonboard_reonboard_msg, remove_msg, reinstall_msg, long_verify_msg, long_status_msg)
        create_report(messages)

def install_agent(oms_bundle):
    """Run container and install the OMS agent, returning HTML results."""
    message = ""
    version = re.search(r'omsagent-\s*([\d.\d-]+)', oms_bundle).group(1)[:-1]
    install_times.clear()
    for image in images:
        container, _, _, _, tmp_path, log_file, html_file, oms_file = setup_vars(image)
        write_log_command("\n[{0}] Install OMS Agent {1} ...".format(image, version), log_file)
        html_file.write("<h1 id='{0}'> Container: {0} <h1>".format(image))
        os.system("docker container stop {0} 2> /dev/null".format(container))
        os.system("docker container rm {0} 2> /dev/null".format(container))
        uid = os.popen("docker run --name {0} -it --privileged=true -d {1}".format(container, image)).read()[:12]
        hostname = image + '-' + uid # uid is the truncated container uid
        hostnames.append(hostname)
        os.system("docker cp omsfiles/ {0}:/home/temp/".format(container))
        os.system("docker exec {0} hostname {1}".format(container, hostname))
        os.system("docker exec {0} {1} -u /home/temp/omsfiles/oms_run_script.py -preinstall".format(container, get_versioned_python(image)))
        os.system("docker exec {0} sh /home/temp/omsfiles/{1} --purge | tee -a {2}".format(container, oms_bundle, tmp_path))
        os.system("docker exec {0} sh /home/temp/omsfiles/{1} --upgrade -w {2} -s {3} | tee -a {4}".format(container, oms_bundle, workspace_id, workspace_key, tmp_path))
        os.system("docker exec {0} {1} -u /home/temp/omsfiles/oms_run_script.py -postinstall".format(container, get_versioned_python(image)))
        os.system("docker exec {0} {1} -u /home/temp/omsfiles/oms_run_script.py -status".format(container, get_versioned_python(image)))
        install_times.update({image: datetime.now()})
        write_log_command("\n[{0}] Inject Logs ...".format(image), log_file)
        inject_logs(container, image)
        append_file(tmp_path, log_file)
        os.remove(tmp_path)
        copy_append_remove(container, image, 'omsresults.out', log_file)
        html_file.write("<h2> Install OMS Agent {0} </h2>".format(version))
        copy_append_remove(container, image, 'omsresults.html', html_file)
        close_files(log_file, html_file, oms_file)
        status = check_workspace_status(container)
        if status == WorkspaceStatus.ONBOARDED:
            message += SUCCESS_TEMPLATE.format("Install Success")
        elif status == WorkspaceStatus.NOT_ONBOARDED:
            message += FAILURE_TEMPLATE.format("Onboarding Failed")
        else:
            message += FAILURE_TEMPLATE.format("Install Failed")
    return message

def upgrade_agent(oms_bundle):
    message = ""
    version = re.search(r'omsagent-\s*([\d.\d-]+)', oms_bundle).group(1)[:-1]
    install_times.clear()
    for image in images:
        container, _, _, _, tmp_path, log_file, html_file, oms_file = setup_vars(image)
        write_log_command("\n[{0}] Upgrade OMS Agent {1} ...".format(image, version), log_file)
        os.system("docker exec {0} sh /home/temp/omsfiles/{1} --upgrade -w {2} -s {3} | tee -a {4}".format(container, oms_bundle, workspace_id, workspace_key, tmp_path))
        os.system("docker exec {0} {1} -u /home/temp/omsfiles/oms_run_script.py -postinstall".format(container, get_versioned_python(image)))
        os.system("docker exec {0} {1} -u /home/temp/omsfiles/oms_run_script.py -status".format(container, get_versioned_python(image)))
        install_times.update({image: datetime.now()})
        inject_logs(container, image)
        append_file(tmp_path, log_file)
        os.remove(tmp_path)
        copy_append_remove(container, image, 'omsresults.out', log_file)
        html_file.write("<h2> Upgrade OMS Agent {0} </h2>".format(version))
        copy_append_remove(container, image, 'omsresults.html', html_file)
        close_files(log_file, html_file, oms_file)
        status = check_workspace_status(container)
        if status == WorkspaceStatus.ONBOARDED:
            message += SUCCESS_TEMPLATE.format("Install Success")
        elif status == WorkspaceStatus.NOT_ONBOARDED:
            message += FAILURE_TEMPLATE.format("Onboarding Failed")
        else:
            message += FAILURE_TEMPLATE.format("Install Failed")
    return message

def inject_logs(container, image):
    """Inject logs."""
    # os.system("docker exec {0} {1} -u /home/temp/omsfiles/oms_run_script.py -injectlogs".format(container, get_versioned_python(image)))
    sleep(60)
    os.system("docker exec {0} {1} -u /home/temp/omsfiles/oms_run_script.py -injectlogs".format(container, get_versioned_python(image)))
        
def verify_data():
    """Verify data end-to-end, returning HTML results."""
    message = ""
    for hostname in hostnames:
        image = hostname.split('-')[0]
        _, _, _, _, _, log_file, html_file, _ = setup_vars(image)
        write_log_command('\n[{0}] Verify E2E Data Results'.format(image), log_file)
        while datetime.now() < (install_times[image] + timedelta(minutes=E2E_DELAY)):
            mins, secs = get_time_diff(datetime.now(), install_times[image] + timedelta(minutes=E2E_DELAY))
            sys.stdout.write('\rE2E propagation delay for {0}: {1} minutes {2} seconds ...'.format(image, mins, secs))
            sys.stdout.flush()
            sleep(1)
        print('')
        minutes, _ = get_time_diff(install_times[image], datetime.now())
        timespan = 'PT{0}M'.format(minutes)
        data = check_e2e(hostname, timespan)

        # write detailed table for image
        html_file.write("<h2> Verify Data from OMS workspace </h2>")
        results = data[image][0]
        log_file.write(image + ':\n' + json.dumps(results, indent=4, separators=(',', ': ')) + '\n')
        # prepend distro column to results row before generating the table
        data = [OrderedDict([('Distro', image)] + results.items())]
        out = json2html.convert(data)
        html_file.write(out)
        close_files(log_file, html_file)

        # write to summary table
        from verify_e2e import success_count
        if success_count == 6:
            message += SUCCESS_TEMPLATE.format("Verify Success")
        elif 0 < success_count < 6:
            from verify_e2e import success_sources, failed_sources
            message += """<td><span style='background-color: #66ff99'>{0} Success</span> <br><br><span style='background-color: red; color: white'>{1} Failed</span></td>""".format(', '.join(success_sources), ', '.join(failed_sources))
        elif success_count == 0:
            message += FAILURE_TEMPLATE.format("Verify Failed")
    return message

def deonboard_reonboard():
    """De-onboard, then re-onboard the agent."""
    message = ""
    for image in images:
        container, _, _, _, tmp_path, log_file, html_file, _ = setup_vars(image)
        write_log_command('\n[{0}] De-onboard and Re-onboard OMS Agent ...'.format(image), log_file)
        html_file.write("<h2> De-onboard and Re-onboard OMS Agent </h2>")
        # set -o pipefail is needed to get the exit code in case the docker exec command fails; otherwise os.system returns the exit code of tee
        try:
            subprocess.check_output("set -o pipefail && docker exec {0} /opt/microsoft/omsagent/bin/omsadmin.sh -X | tee -a {1}".format(container, tmp_path), shell=True, executable='/bin/bash')
            try:
                subprocess.check_output("set -o pipefail && docker exec {0} /opt/microsoft/omsagent/bin/omsadmin.sh -w {1} -s {2} | tee -a {3}".format(container, workspace_id, workspace_key, tmp_path), shell=True, executable='/bin/bash')
                message += SUCCESS_TEMPLATE.format("De-onboarding and Re-onboarding Success")
            except subprocess.CalledProcessError as e:
                message += FAILURE_TEMPLATE.format("De-onboarding Success; Re-onboarding Failure")
        except subprocess.CalledProcessError as e:
            message += FAILURE_TEMPLATE.format("De-onboarding Failure")
        append_file(tmp_path, log_file)
        os.remove(tmp_path)
        close_files(log_file, html_file)
    return message

def remove_agent():
    """Remove the OMS agent, returning HTML results."""
    message = ""
    for image in images:
        container, _, _, _, tmp_path, log_file, html_file, oms_file = setup_vars(image)
        write_log_command('\n[{0}] Remove OMS Agent ...'.format(image), log_file)
        os.system("docker exec {0} {1} -u /home/temp/omsfiles/oms_run_script.py -copyomslogs".format(container, get_versioned_python(image)))
        copy_append_remove(container, image, 'copyofomsagent.log', oms_file)
        os.system("docker exec {0} sh /home/temp/omsfiles/{1} --remove | tee -a {2}".format(container, oms_bundle, tmp_path))
        os.system("docker exec {0} {1} -u /home/temp/omsfiles/oms_run_script.py -status".format(container, get_versioned_python(image)))
        append_file(tmp_path, log_file)
        os.remove(tmp_path)
        copy_append_remove(container, image, 'omsresults.out', log_file)
        html_file.write("<h2> Remove OMS Agent </h2>")
        copy_append_remove(container, image, 'omsresults.html', html_file)
        close_files(log_file, html_file, oms_file)
        status = check_workspace_status(container)
        if status == WorkspaceStatus.ONBOARDED:
            message += FAILURE_TEMPLATE.format("Remove Failed")
        elif status == WorkspaceStatus.NOT_ONBOARDED:
            message += FAILURE_TEMPLATE.format("Onboarding Failed")
        else:
            message += SUCCESS_TEMPLATE.format("Remove Success")
    return message

def reinstall_agent():
    """Reinstall the OMS agent, returning HTML results."""
    message = ""
    for image in images:
        container, _, _, _, tmp_path, log_file, html_file, oms_file = setup_vars(image)
        write_log_command("\n[{0}] Reinstall OMS Agent ...".format(image), log_file)
        os.system("docker exec {0} sh /home/temp/omsfiles/{1} --upgrade | tee -a {2}".format(container, oms_bundle, tmp_path))
        os.system("docker exec {0} /opt/microsoft/omsagent/bin/omsadmin.sh -w {1} -s {2} | tee -a {3}".format(container, workspace_id, workspace_key, tmp_path))
        os.system("docker exec {0} {1} -u /home/temp/omsfiles/oms_run_script.py -postinstall".format(container, get_versioned_python(image)))
        os.system("docker exec {0} {1} -u /home/temp/omsfiles/oms_run_script.py -status".format(container, get_versioned_python(image)))
        append_file(tmp_path, log_file)
        os.remove(tmp_path)
        copy_append_remove(container, image, 'omsresults.out', log_file)
        html_file.write("<h2> Reinstall OMS Agent </h2>")
        copy_append_remove(container, image, 'omsresults.html', html_file)
        close_files(log_file, html_file, oms_file)
        status = check_workspace_status(container)
        if status == WorkspaceStatus.ONBOARDED:
            message += SUCCESS_TEMPLATE.format("Reinstall Success")
        elif status == WorkspaceStatus.NOT_ONBOARDED:
            message += FAILURE_TEMPLATE.format("Onboarding Failed")
        else:
            message += FAILURE_TEMPLATE.format("Reinstall Failed")
    return message

def check_status():
    """Check agent status."""
    message = ""
    for image in images:
        container, _, _, _, _, log_file, html_file, oms_file = setup_vars(image)
        write_log_command("\n[{0}] Check Status ...".format(image), log_file)
        os.system("docker exec {0} {1} -u /home/temp/omsfiles/oms_run_script.py -status".format(container, get_versioned_python(image)))
        copy_append_remove(container, image, 'omsresults.out', log_file)
        html_file.write("<h2> Check OMS Agent Status </h2>")
        copy_append_remove(container, image, 'omsresults.html', html_file)
        close_files(log_file, html_file, oms_file)
        if os.system('docker exec {0} /opt/microsoft/omsagent/bin/omsadmin.sh -l'.format(container)) == 0:
            out = str(subprocess.check_output('docker exec {0} /opt/microsoft/omsagent/bin/omsadmin.sh -l'.format(container), shell=True))
            if 'Onboarded' in out:
                message += SUCCESS_TEMPLATE.format("Agent Running")
            elif 'Warning' in out:
                message += FAILURE_TEMPLATE.format("Agent Registered, Not Running")
            elif 'Saved' in out:
                message += FAILURE_TEMPLATE.format("Agent Not Running, Not Registered")
            elif 'Failure' in out:
                message += FAILURE_TEMPLATE.format("Agent Not Running, Not Onboarded")
        else:
            message += FAILURE_TEMPLATE.format("Agent Not Installed")
    return message

def purge_delete_agent():
    """Purge the OMS agent and delete container."""
    for image in images:
        container, _, _, omslog_path, tmp_path, log_file, html_file, oms_file = setup_vars(image)
        write_log_command('\n[{0}] Purge OMS Agent ...'.format(image), oms_file)
        os.system("docker exec {0} {1} -u /home/temp/omsfiles/oms_run_script.py -copyomslogs".format(container, get_versioned_python(image)))
        copy_append_remove(container, image, 'copyofomsagent.log', oms_file)
        os.system("docker exec {0} sh /home/temp/omsfiles/{1} --purge | tee -a {2}".format(container, oms_bundle, tmp_path))
        append_file(tmp_path, log_file)
        os.remove(tmp_path)
        append_file(omslog_path, log_file)
        close_files(log_file, html_file, oms_file)
        os.system("docker container stop {0}".format(container))
        os.system("docker container rm {0}".format(container))

def create_report(messages):
    """Compile the final HTML report."""
    install_msg, verify_msg, instantupgrade_install_msg, instantupgrade_verify_msg, deonboard_reonboard_msg, remove_msg, reinstall_msg, long_verify_msg, long_status_msg = messages

    # summary table
    imagesth = ""
    resultsth = ""
    for image in images:
        imagesth += """
                <th>{0}</th>""".format(image)
        resultsth += """
                <th><a href='#{0}'>{0} results</a></th>""".format(image)

    # pre-compile instant-upgrade summary
    if instantupgrade_install_msg and instantupgrade_verify_msg:
        instantupgrade_summary = """
        <tr>
          <td>Instant Upgrade Install Status</td>
          {0}
        </tr>
        <tr>
          <td>Instant Upgrade Verify Data</td>
          {1}
        </tr>
        """.format(instantupgrade_install_msg, instantupgrade_verify_msg)
    else:
        instantupgrade_summary = ""

    # pre-compile long-running summary
    if long_verify_msg and long_status_msg:
        long_running_summary = """
        <tr>
          <td>Long-Term Verify Data</td>
          {0}
        </tr>
        <tr>
          <td>Long-Term Status</td>
          {1}
        </tr>
        """.format(long_verify_msg, long_status_msg)
    else:
        long_running_summary = ""

    statustable = """
    <table>
      <caption><h2>Test Result Table</h2><caption>
      <tr>
        <th>Distro</th>
        {0}
      </tr>
      <tr>
        <td>Install OMSAgent</td>
        {1}
      </tr>
      <tr>
        <td>Verify Data</td>
        {2}
      </tr>
      {3}
      <tr>
        <td>Deonboard and Reonboard OMSAgent</td>
        {4}
      </tr>
      <tr>
        <td>Remove OMSAgent</td>
        {5}
      </tr>
      <tr>
        <td>Reinstall OMSAgent</td>
        {6}
      </tr>
      {7}
      <tr>
        <td>Result Link</td>
        {8}
      <tr>
    </table>
    """.format(imagesth, install_msg, verify_msg, instantupgrade_summary, deonboard_reonboard_msg, remove_msg, reinstall_msg, long_running_summary, resultsth)
    result_html_file.write(statustable)

    # Create final html & log file
    for image in images:
        append_file('results/{}/result.log'.format(image), result_log_file)
        append_file('results/{}/result.html'.format(image), result_html_file)
    
    result_log_file.close()
    htmlend = """
    </body>
    </html>
    """
    result_html_file.write(htmlend)
    result_html_file.close()

def archive_results():
    archive_path = 'results/' + datetime.now().strftime('%Y-%m-%d %H.%M.%S')
    os.mkdir(archive_path)
    for f in [f for f in glob('results/*') if f.split('/')[1] in images or f.startswith('results/finalresult') ]:
        shutil.move(os.path.join(f), os.path.join(archive_path))

def cleanup():
    sys.stdout.write('Initiating cleanup\n')
    sys.stdout.flush()
    archive_results()
    for p in procs.items():
        if p[1].poll() is None:
            p[1].kill()
    for image in images:
        container = image + '-container'
        os.system('docker kill {} 2> /dev/null'.format(container))
        os.system('docker rm --force {} 2> /dev/null'.format(container))
    sleep(1)

if __name__ == '__main__':
    if not os.environ.get('SUBPROCESS'):
        atexit.register(cleanup)
    main()
