'''
   OMS Log Collector to collect logs and command line outputs for
   troubleshooting OMS Linux Agent (Github, Extension & Container)
   issues by support personnel

   Authors, Reviewers & Contributors :
                 KR Kandavel Azure CAT PM
                 Keiko Harada OMS PM
                 Laura Galbraith OMS SE
                 Jim Britt Azure CAT PM
                 Gary Keong OMS Eng. Mgr.
                 Adrian Doyle CSS PM
                 Steve Chilcoat CSS Esc. Eng.

   Date        : 2017-07-20
   Version     : 2.3
   
'''
from __future__ import print_function
# coding: UTF-8
import os
import subprocess
import logging
import sys, getopt
import datetime

if "check_output" not in dir( subprocess ): # duck punch it in!
        def check_output(*popenargs, **kwargs):
            r"""Run command with arguments and return its output as a byte string.

            Backported from Python 2.7 as it's implemented as pure python on stdlib.

            >>> check_output(['/usr/bin/python', '--version'])
            Python 2.6.2
            """
            process = subprocess.Popen(stdout=subprocess.PIPE, *popenargs, **kwargs)
            output, unused_err = process.communicate()
            retcode = process.poll()
            if retcode:
                cmd = kwargs.get("args")
                if cmd is None:
                    cmd = popenargs[0]
                error = subprocess.CalledProcessError(retcode, cmd)
                error.output = output
                raise error
            return output

        subprocess.check_output = check_output

'''
Get OMS container ID for running docker command inside container
'''
def getOMSAgentContainerID():
    cmd='docker ps | grep -i microsoft/oms | grep -v grep'
    out=execCommand(cmd)
    strs=out.split(' ')
    omsContainerID=strs[0]
    return omsContainerID

'''
Get OMS container Name for running docker command inside container
'''
def getOMSAgentContainerName():
    cmd='docker ps | grep -i microsoft/oms | grep -v grep'
    out=execCommand(cmd)
    strs=out.split(' ')
    omsContainerName=strs[-1]
    return omsContainerName

'''
Use docker command to collect OMS Linux Agent (omsagent container) logs
from container host
'''
def runDockerCommands(omsContainerID):
    cmd='docker info'
    out=execCommand(cmd)
    writeLogCommand(cmd)
    writeLogOutput(out)
    cmd='docker ps -a'
    out=execCommand(cmd)
    writeLogCommand(cmd)
    writeLogOutput(out)
    cmd='docker inspect omsagent'
    out=execCommand(cmd)
    writeLogCommand(cmd)
    writeLogOutput(out)
    cmd='docker logs omsagent 1>/tmp/omscontainer.log 2>&1'
    out=execCommand2(cmd)
    writeLogCommand(cmd)
    writeLogOutput(out)
    cmd='cat /tmp/omscontainer.log'
    out=execCommand(cmd)
    writeLogOutput(str(out))
    cmd='docker inspect omsagent | grep -I -A 4 label'
    out=execCommand(cmd)
    writeLogCommand(cmd)
    writeLogOutput(out)
    return 0

'''
Use docker command to collect OMS Linux Agent (omsagent container) logs
from container hosting OMS Agent
'''
def runContainerCommands(omsContainerName):
    cmd='docker exec omsagent df -k'
    out=execCommand(cmd)
    writeLogCommand(cmd)
    writeLogOutput(out)
    cmd='docker exec omsagent ps -ef | grep -i oms | grep -v grep'
    out=execCommand(cmd)
    writeLogCommand(cmd)
    writeLogOutput(out)
    cmd='docker exec omsagent ps -ef | grep -i omi | grep -v grep'
    out=execCommand(cmd)
    writeLogOutput(cmd)
    writeLogOutput(out)
    cmd='docker exec omsagent /opt/microsoft/omsagent/bin/omsadmin.sh -l > /tmp/oms.status'
    writeLogCommand(cmd)
    out=execCommand2(cmd)
    cmd='cat /tmp/oms.status'
    out=execCommand(cmd)
    writeLogOutput(out)
    cmd='docker exec omsagent /opt/omi/bin/omicli ei root/cimv2 Container_ContainerStatistics' 
    out=execCommand(cmd)
    writeLogCommand(cmd)
    writeLogOutput(out)
    cmd='docker exec omsagent /opt/omi/bin/omicli ei root/cimv2 Container_ContainerInventory'
    out=execCommand(cmd)
    writeLogCommand(cmd)
    writeLogOutput(out)
    return 0

'''
Use docker command to copy logs from container hosting OMS Agent
'''
def copyContainerFiles(omsContainerName, omsLinuxType):
    cmd='docker exec omsagent find ' + '. ' + '/var/opt/microsoft/omsagent ' + '-name ' + 'omsagent.log'
    file=execCommand(cmd)
    cmd='docker cp omsagent:' + file[:len(file)-1] + ' /tmp/omslogs/container'
    out=execCommand(cmd)
    writeLogCommand(cmd)
    cmd='docker cp omsagent:' + '/var/opt/microsoft/omsconfig/omsconfig.log ' + '/tmp/omslogs/container'
    out=execCommand(cmd)
    writeLogCommand(cmd)
    cmd='docker cp omsagent:' + '/var/opt/microsoft/scx/log/scx.log ' + '/tmp/omslogs/container'
    out=execCommand(cmd)
    writeLogCommand(cmd)
    cmd='docker cp omsagent:' + '/etc/opt/microsoft/omsagent/* ' + '/tmp/omslogs/container/WSData'
    out=execCommand(cmd)
    writeLogCommand(cmd)
    if(omsLinuxType == 'Ubuntu'):
       cmd='docker cp omsagent:' + '/var/log/syslog /tmp/omslogs/container'
    else:
       cmd='docker cp omsagent:' + '/var/log/messages /tmp/omslogs/container'
    out=execCommand(cmd)
    writeLogCommand(cmd)
    return 0

'''
Run extension (Azure Agent) specific commands
'''
def runExtensionCommands():
    cmd='waagent -version'
    out=execCommand(cmd)
    writeLogCommand(cmd)
    writeLogOutput(out)
    return 0

'''
Run common OS level commands needed for OMS agent troubleshooting
'''
def runCommonCommands():
    cmd='df -k'
    out=execCommand(cmd)
    writeLogCommand(cmd)
    writeLogOutput(out)
    cmd='ps -ef | grep -i oms | grep -v grep'
    out=execCommand(cmd)
    writeLogCommand(cmd)
    writeLogOutput(out)
    cmd='ps -ef | grep -i omi | grep -v grep'
    out=execCommand(cmd)
    writeLogCommand(cmd)
    writeLogOutput(out)
    cmd='ps aux --sort=-pcpu | head -10'
    out=execCommand(cmd)
    writeLogCommand(cmd)
    writeLogOutput(out)
    cmd='ps aux --sort -rss | head -10'
    out=execCommand(cmd)
    writeLogCommand(cmd)
    writeLogOutput(out)
    cmd='ps aux --sort -vsz | head -10'
    out=execCommand(cmd)
    writeLogCommand(cmd)
    writeLogOutput(out)
    cmd='ps -e -o pid,ppid,user,etime,time,pcpu,nlwp,vsz,rss,pmem,args | grep -i omsagent | grep -v grep'
    out=execCommand(cmd)
    writeLogCommand(cmd)
    writeLogOutput(out)
    cmd='/opt/microsoft/omsagent/bin/omsadmin.sh -l > /tmp/oms.status'
    out=execCommand(cmd)
    writeLogCommand(cmd)
    cmd='cat /tmp/oms.status'
    out=execCommand(cmd)
    writeLogOutput(out)
    return 0

'''
Run Ubuntu OS specific commands needed for OMS agent troubleshooting
'''
def runUbuntuCommands(omsInstallType):
    if(omsInstallType == 3):
       cmd='docker exec omsagent uname -a'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
       cmd='docker exec omsagent apt show omsagent'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
       cmd='docker exec omsagent apt show omsconfig'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
    else:
       cmd='uname -a'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
       cmd='apt show omsagent'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
       cmd='apt show omsconfig'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
    return 0

'''
Run CentOS specific commands needed for OMS agent troubleshooting
'''
def runCentOSCommands(omsInstallType):
    if(omsInstallType == 3):
       cmd='docker exec omsagent uname -a'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
       cmd='docker exec omsagent rpm -qi omsagent'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
       cmd='docker exec omsagent rpm -qi omsconfig'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
    else:
       cmd='uname -a'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
       cmd='rpm -qi omsagent'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
       cmd='rpm -qi omsconfig'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
    return out

'''
Run Redhat OS specific commands needed for OMS agent troubleshooting
'''
def runRedhatCommands(omsInstallType):
    if(omsInstallType == 3):
       cmd='docker exec omsagent uname -a'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
       cmd='docker exec omsagent rpm -qi omsagent'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
       cmd='docker exec omsagent rpm -qi omsconfig'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
    else:
       cmd='uname -a'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
       cmd='rpm -qi omsagent'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
       cmd='rpm -qi omsconfig'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
    return 0

'''
Run Oracle OS specific commands needed for OMS agent troubleshooting
'''
def runOracleCommands(omsInstallType):
    if(omsInstallType == 3):
       cmd='docker exec omsagent uname -a'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
       cmd='docker exec omsagent rpm -qi omsagent'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
       cmd='docker exec omsagent rpm -qi omsconfig'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
    else:
       cmd='uname -a'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
       cmd='rpm -qi omsagent'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
       cmd='rpm -qi omsconfig'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
    return 0

'''
Run Suse OS specific commands needed for OMS agent troubleshooting
'''
def runSLESCommands(omsInstallType):
    if(omsInstallType == 3):
       cmd='docker exec omsagent uname -a'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
       cmd='docker exec omsagent rpm -qi omsagent'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
       cmd='docker exec omsagent rpm -qi omsconfig'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
    else:
       cmd='uname -a'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
       cmd='rpm -qi omsagent'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
       cmd='rpm -qi omsconfig'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
    return 0

'''
Run Debian OS specific commands needed for OMS agent troubleshooting
'''
def runDebianCommands(omsInstallType):
    if(omsInstallType == 3):
       cmd='docker exec omsagent uname -a'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
       cmd='docker exec omsagent apt show omsagent'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
       cmd='docker exec omsagent apt show omsconfig'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
    else:
       cmd='uname -a'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
       cmd='apt show omsagent'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
       cmd='apt show omsconfig'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
    return 0

'''
Copy common logs for all 3 types of OMS agents into /tmp/omslogs
'''
def copyCommonFiles(omsLinuxType):
    cmd='cp /var/opt/microsoft/omsagent/log/omsagent* /tmp/omslogs'
    out=execCommand2(cmd)
    writeLogCommand(cmd)
    cmd='cp /var/opt/microsoft/omsconfig/omsconfig* /tmp/omslogs'
    out=execCommand(cmd)
    writeLogCommand(cmd)
    cmd='cp /var/opt/omi/log/omi* /tmp/omslogs'
    out=execCommand(cmd)
    writeLogCommand(cmd)
    cmd='cp /var/opt/microsoft/scx/log/scx* /tmp/omslogs'
    out=execCommand2(cmd)
    writeLogCommand(cmd)
    cmd='mkdir -p /tmp/omslogs/dscconfiguration'
    out=execCommand(cmd)
    writeLogCommand(cmd)
    cmd='cp -rf /etc/opt/omi/conf/omsconfig/configuration/* /tmp/omslogs/dscconfiguration'
    out=execCommand(cmd)
    writeLogCommand(cmd)
    cmd='mkdir -p /tmp/omslogs/WSData'
    out=execCommand(cmd)
    writeLogCommand(cmd)
    cmd='cp -rf /etc/opt/microsoft/omsagent/* /tmp/omslogs/WSData'
    out=execCommand(cmd)
    writeLogCommand(cmd)
    if(omsLinuxType == 'Ubuntu'):
       cmd='cp /var/log/syslog* /tmp/omslogs'
    else:
       cmd='cp /var/log/messages* /tmp/omslogs'
    out=execCommand(cmd)
    writeLogCommand(cmd)
    return 0

'''
Copy OMS agent (Extension) specific logs into /tmp/omslogs
'''
def copyExtensionFiles():
    cmd='cp /var/log/waagent.log /tmp/omslogs/vmagent'
    out=execCommand(cmd)
    writeLogCommand(cmd)
    cmd='cp -R /var/log/azure/Microsoft.EnterpriseCloud.Monitoring.OmsAgentForLinux /tmp/omslogs/extension/log'
    out=execCommand(cmd)
    writeLogCommand(cmd)
    cmd='ls /var/lib/waagent | grep -i Microsoft.EnterpriseCloud.Monitoring.OmsAgentForLinux-'
    file=execCommand(cmd)
    lfiles=file.split()
    print(lfiles)
    cmd='cp -R /var/lib/waagent/' + lfiles[0] + '/status ' + '/tmp/omslogs/extension/lib'
    print(cmd)
    out=execCommand(cmd)
    writeLogCommand(cmd)
    cmd='cp -R /var/lib/waagent/' + lfiles[0] + '/config ' + '/tmp/omslogs/extension/lib'
    out=execCommand(cmd)
    writeLogCommand(cmd)
    return 0

'''
Copy Update Management Solution logs into /tmp/omslogs/updateMgmtlogs
'''
def copyUpdateFiles():
    cmd='mkdir -p /tmp/omslogs/updateMgmtlogs'
    out=execCommand(cmd)
    writeLogCommand(cmd)

    cmd='cp /var/opt/microsoft/omsagent/log/urp.log /tmp/omslogs/updateMgmtlogs'
    out=execCommand(cmd)
    writeLogCommand(cmd)

    cmd='cp /etc/opt/omi/conf/omsconfig/configuration/CompletePackageInventory.xml* /tmp/omslogs/updateMgmtlogs'
    out=execCommand(cmd)
    writeLogCommand(cmd)
    
    cmd='cp /var/opt/microsoft/omsagent/run/automationworker/*.* /tmp/omslogs/updateMgmtlogs'
    out=execCommand(cmd)
    writeLogCommand(cmd)

    cmd='sudo find /var/opt/microsoft/ -name worker.log -exec cp -n {} /tmp/omslogs/updateMgmtlogs \;'
    out=execCommand(cmd)
    writeLogCommand(cmd)
    return 0

'''
Return the package manager on the system
'''

def GetPackageManager():
    # choose default - almost surely one will match.
    for pkg_mgr in ('apt-get', 'zypper', 'yum'):
        code = execCommand2('which ' + pkg_mgr)
        if code is 0:
            return pkg_mgr                        
    return None

'''
obtain the current Available updates on the system
'''


def GetUpdates():
    mgr = GetPackageManager()
    if mgr == None:
        print("Unable to find one of 'apt', 'yum', or 'zypper'.")
        return None
    if mgr == 'apt-get':
        cmd = 'LANG=en_US.UTF8 apt-get -s dist-upgrade | grep "^Inst"'
    elif mgr == 'yum':
        cmd = 'sudo yum check-update '
    elif mgr == 'zypper':
        cmd = 'zypper -q lu'
    return cmd


'''
Remove temporary files under /tmp/omslogs once it is archived
'''
def removeTempFiles():
    cmd='rm -R -rf /tmp/omslogs'
    out=execCommand(cmd)
    print(cmd)
    print(out)
    cmd='rm -rf /tmp/oms.status'
    out=execCommand(cmd)
    print(cmd)
    print(out)
    return 0

'''
Estimate disk space required for OMS agent (Github)
'''
def estCommonFileSize(omsLinuxType):
    reqSize=0
    folderName='/var/opt/microsoft/omsagent/log/'
    reqSize+=getFolderSize(folderName)
    folderName='/etc/opt/microsoft/omsagent/'
    reqSize+=getFolderSize(folderName)
    reqSize+=getFileSize('/var/opt/microsoft/omsconfig/omsconfig.log')
    reqSize+=getFileSize('/var/opt/microsoft/scx/log/scx.log')
    if(omsLinuxType == 'Ubuntu'):
       reqSize+=getFileSize('/var/log/syslog')
    else:
       reqSize+=getFileSize('/var/log/messages')
    return reqSize

'''
Estimate disk space required for OMS agent (Extension)
'''
def estExtensionFileSize(omsLinuxType):
    reqSize=0
    folderName='/var/log/azure/Microsoft.EnterpriseCloud.Monitoring.OmsAgentForLinux'
    reqSize+=getFolderSize(folderName)
    reqSize+=getFileSize('/var/log/waagent.log')
    folderName='/var/lib/waagent/Microsoft.EnterpriseCloud.Monitoring.OmsAgentForLinux-*'
    reqSize+=getFolderSize(folderName)
    return reqSize

'''
Check if /tmp has adequate disk space to copy logs and command outputs
'''
def chkDiskFreeSpace(estSize, estExtSize, cmdSize):
    tmpSpace = 0
    arcSize = (estSize + estExtSize + cmdSize) * 0.1
    totSize = (estSize + estExtSize + cmdSize) + arcSize
    print('*' * 80)
    print("1. Disk space required to copy Common files in /tmp       : ", int(estSize / 1024), 'KBytes')
    print("2. Disk space required to copy Extension files in /tmp    : ", int(estExtSize / 1024), 'KBytes')
    print("3. Disk space required for command outputs in /tmp        : ", int(cmdSize / 1024), 'KBytes')
    print("4. Disk space required to archive files in /tmp           : ", int(arcSize / 1024), 'KBytes')
    print("5. Total disk space required in /tmp                      : ", int(totSize / 1024), 'KBytes')
    print('*' * 80)
    print("Files created in step 1, 2 & 3 are temporary and deleted at the end")
    print('*' * 80)
    stat= os.statvfs('/tmp')
    # use f_bfree for superuser, or f_bavail if filesystem
    # has reserved space for superuser
    freeSpace=stat.f_bfree*stat.f_bsize
    if(totSize < freeSpace): 
          print('Enough space available in /tmp to store logs...')
          print('*' * 80)
    else:
          print('Not enough free space available in /tmp to store logs...')
          print('*' * 80)
          tmpSpace = 1
    return tmpSpace

'''
Checks if OMS Linux Agent install directory is present, if not then it recommends running
the OMS Linux Agent installation before collecting logs for troubleshooting
'''
def chkOMSAgentInstallStatus(omsInstallType):
    omsInstallDir = [ "/var/opt/microsoft/omsagent",
                      "/var/opt/microsoft/omsconfig"
                    ]
    if(omsInstallType != 3):        
        for dir in omsInstallDir:
            if(not os.path.exists(dir)):
               return 1
    return 0           

'''
Check the type (Github, Extension, Container) of agent running in Linux machine
'''
def chkOMSAgentInstallType():
    omsInstallType=0
    cmd='ls /var/lib/waagent | grep -i Microsoft.EnterpriseCloud.Monitoring.OmsAgentForLinux-'
    file=execCommand2(cmd)
    if(file == 1):
      omsExtension = False
    else:
      file=execCommand(cmd)
      lfiles=file.split()
      path='/var/lib/waagent/' + lfiles[0]
      print(path)
      omsExtension=os.path.exists(path)
      print(omsExtension) 
    if(omsExtension == True):
         out="OMS Linux Agent is installed through VM Extension...\n"
         omsInstallType=1
    elif(omsExtension == False):
         path='/var/opt/microsoft/omsagent'
         omsAgent=os.path.exists(path)
         if(omsAgent == True):
           out="OMS Linux Agent installed with NO VM Extension (Github)...\n"
           omsInstallType=2
         elif(omsAgent == False):
           cmd='which docker 1>/dev/null 2>&1'
           out=execCommand2(cmd)
           writeLogCommand(cmd)
           writeLogOutput(out)
           if(out == 0):
               cmd='docker ps | grep -i microsoft/oms | grep -v grep'
               out=execCommand(cmd)
               count=out.splitlines()
               if(len(count) == 1):
                  out="Containerized OMS Linux Agent is installed...\n"
                  omsInstallType=3
           else:
               out="No OMS Linux Agent installed on this machine...\n"
               omsInstallType=0
    else:
         out="No OMS Linux Agent installed on this machine...\n"
         omsInstallType=0

    writeLogOutput(out)     
    return omsInstallType

'''
Get size in bytes of a folder 
'''
def getFolderSize(foldername):
    fileSize=0
    for root, dirs, files in os.walk(foldername):
        fileSize=sum(os.path.getsize(os.path.join(root, name)) for name in files)
    return fileSize

'''
Get file size, ignoring missing files
'''
def getFileSize(filename):
    if os.path.exists(filename):
         return os.path.getsize(filename)
    else:
         return 0

'''
Common logic to run any command and check/get its output for further use
'''
def execCommand(cmd):
    try:
        out = subprocess.check_output(cmd, shell=True)

        if sys.version_info >= (3,):
            out = out.decode()

        return out
    except subprocess.CalledProcessError as e:
        print(e.returncode)
        return (e.returncode)

'''
Common logic to run any command and check if it is success/failed
'''
def execCommand2(cmd):
    try:
        out = subprocess.call(cmd, shell=True)
        return out
    except subprocess.CalledProcessError as e:
        print(e.returncode)
        return (e.returncode)

'''
Common logic to run any command and get always output irrespective of return code
'''
def execCommand_always_output(cmd):
    try:
        out = subprocess.check_output(cmd, shell=True)
        return out
    except subprocess.CalledProcessError as e:
        print(e.returncode)
        return e.output


'''
Common logic to save command outputs into /tmp/omslogs/omslinux.out
'''
def writeLogOutput(out):
    if(type(out) != str): out=str(out)
    outFile.write(out + '\n')
    outFile.write('-' * 80)
    outFile.write('\n')
    return

'''
Common logic to save command itself into /tmp/omslogs/omslinux.out
'''
def writeLogCommand(cmd):
    print(cmd)
    outFile.write(cmd + '\n')
    outFile.write('=' * 40)
    outFile.write('\n')
    return

'''
Compress all logs & command o/p files in a TAR ball for sending it to Support
'''
def compressOMSLog(source, target):
    cmd='tar -cvzf ' + target + ' ' + source
    out=execCommand(cmd)
    print(cmd)
    print(out)
    return 0

'''
Logic to validate input arguments before collecting the logs 
'''    
def inpArgCheck(argv):
    global srnum, comname
    srnum = ''
    comname = ''
    try:
        opts, args = getopt.getopt(argv, "hs:c:", ['srnum=', 'comname='])
    except getopt.GetoptError:
        print('Usage: sudo python omsagentlog.py [-h] -s <SR Number> [-c <Company Name>]')
        return 2
    if(len(argv) == 0):
        print('Usage: sudo python omsagentlog.py [-h] -s <SR Number> [-c <Company Name>]')
        return 1
    for opt, arg in opts:
        if (opt == '-h'):
           print('Usage: sudo python omsagentlog.py [-h] -s <SR Number> [-c <Company Name>]')
           return 1
        elif opt in ('-s', '--srnum'):
             srnum = arg
        elif opt in ('-c', '--comname'):
             comname = arg
    return 0

'''
Main() logic for log collection, calling the above functions 
'''  
ret=inpArgCheck(sys.argv[1:])
if(ret == 1 or ret == 2):
    sys.exit(1)
print('SR Number : ', srnum)
print('Company Name :', comname)

global logger
outDir='/tmp/omslogs'
outFile=outDir + '/omslinux.out'
compressFile='/tmp/omslinuxagentlog' + '-' + srnum + '-' + str(datetime.datetime.utcnow().isoformat()) + '.tgz'
print(compressFile)

centRHOraPath='/etc/system-release'
ubuntuPath='/etc/lsb-release'
slesDebianPath='/etc/os-release'
fedoraPath='/etc/fedora-release'

try:
    '''
    Initialize routine to create necessary files and directories for storing logs & command o/p
    '''
    cmd='mkdir -p ' + outDir + '/ '
    out=execCommand(cmd)
    outFile = open(outFile, 'w') 
    writeLogOutput('SR Number : ' + srnum + '   Company Name : ' + comname)
    
    curutctime=datetime.datetime.utcnow()
    logtime='Log Collection Start Time (UTC) : %s' % (curutctime) 
    print(logtime)
    writeLogOutput(logtime)
    writeLogCommand(cmd)
    writeLogOutput(out)

    cmd='hostname -f'
    out=execCommand(cmd)
    writeLogCommand(cmd)
    writeLogOutput(out)

    cmd='python -V'
    writeLogCommand(cmd)
    writeLogOutput(sys.version)

    '''
    Logic to check what Linux distro is running in machine
    '''
    if (os.path.isfile(centRHOraPath)):
       cmd='cat %s' % centRHOraPath
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
       strs=out.split(' ')
       linuxType=strs[0]
       linuxVer=strs[3]
       if(linuxType == 'Red'):
           linuxType=strs[0] + strs[1]
           linuxVer=strs[6]
    elif (os.path.isfile(ubuntuPath)):
       cmd='cat %s' % ubuntuPath
       out=execCommand(cmd)
       writeLogCommand(out)
       writeLogOutput(out)
       lines=out.split('\n')
       strs=lines[0].split('=')
       linuxType=strs[1]
    elif (os.path.isfile(slesDebianPath)):
       cmd='cat %s' % slesDebianPath
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
       lines=out.split('\n')
       strs=lines[0].split('=')
       print(strs[1])
       if (strs[1].find('SLES') != -1):
          linuxType='SLES'
       elif (strs[1].find('Debian') != -1):
          linuxType='Debian'
       else:
          msg = 'Unsupported Linux OS...Stopping OMS Log Collection...%s' % linuxType
          print(msg)
          writeLogOutput(msg)
          sys.exit() 
    else:
       msg = 'Unsupported Linux OS...Stopping OMS Log Collection...%s' % linuxType
       print(msg)
       writeLogOutput(msg)
       sys.exit(1)

    '''
    Logic to check which OMS Linux agent type is installed in machine
    [0 - No Agent, Extension=1, Github=2, Container=3]
    '''
    writeLogOutput('Linux type installed is...%s' % linuxType)
    omsInstallType=chkOMSAgentInstallType()
    if(omsInstallType == 1):
       cmd='mkdir -p ' + outDir + '/vmagent'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
       cmd='mkdir -p ' + outDir + '/extension/log'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
       cmd='mkdir -p ' + outDir + '/extension/lib'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
       estSize=estCommonFileSize(linuxType)
       estExtSize=estExtensionFileSize(linuxType)
       cmdSize=10 * 1024
       tmpSpace=chkDiskFreeSpace(estSize, estExtSize, cmdSize)
       if(tmpSpace == 0):
          copyCommonFiles(linuxType)
          copyExtensionFiles()
          runExtensionCommands()
          copyUpdateFiles()
       else:
          sys.exit(1)
    elif(omsInstallType == 2):
       estSize=estCommonFileSize(linuxType)
       cmdSize=10 * 1024
       tmpSpace=chkDiskFreeSpace(estSize, 0, cmdSize)
       if(tmpSpace == 0):
          copyCommonFiles(linuxType)
          copyUpdateFiles()
       else:
          sys.exit(1)
    elif(omsInstallType == 3):
       cmd='mkdir -p ' + outDir + '/container'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
       cmd='mkdir -p ' + outDir + '/container/WSData'
       out=execCommand(cmd)
       writeLogCommand(cmd)
       writeLogOutput(out)
       omsContainerID=getOMSAgentContainerID()
       omsContainerName=getOMSAgentContainerName()
       estSize=estCommonFileSize(linuxType)
       cmdSize=10 * 1024
       tmpSpace=chkDiskFreeSpace(estSize, 0, cmdSize)
       if(tmpSpace == 0):
            runDockerCommands(omsContainerID)
            copyContainerFiles(omsContainerName, linuxType)
            runContainerCommands(omsContainerName)
       else:
          sys.exit(1)
    else:
       msg='No OMS Linux Agent installed on this machine...Stopping Log Collection...%s' % omsInstallType
       print(msg)
       writeLogOutput(msg)
       sys.exit(1)

    '''
    Checks if OMS Linux Agent install directory is present, if not then it recommends
    running the OMS Linux Agent installation before collecting logs for troubleshooting
    '''
    writeLogOutput('OMS Linux agent installed is (0 - No Agent 1 - Extension, 2 - GitHub, 3 - Container...%s' % omsInstallType)
    omsInstallStatus=chkOMSAgentInstallStatus(omsInstallType)
    if(omsInstallStatus != 0):
        msg='OMS Linux Agent install directories under /var/opt/microsoft are missing...'
        writeLogOutput(msg)
        print('*' * 80)
        print('OMS Linux Agent install directories are not present')
        print('please run OMS Linux Agent install script')
        print('For details on installing OMS Agent, please refer documentation')
        print('https://docs.microsoft.com/en-us/azure/log-analytics/log-analytics-agent-linux')
        print('*' * 80)
        sys.exit(1)
    else:
        msg='OMS Linux Agent install directories under /var/opt/microsoft are present...'
        writeLogOutput(msg)

    '''
    Call OS specific routines to run commands and save its o/p
    to /tmp/omslogs/omslinux.out
    '''
    print('Linux type installed is...%s' % linuxType)
    if(linuxType == 'CentOS'):
       runCentOSCommands(omsInstallType)
    elif(linuxType == 'RedHat'):
       runRedhatCommands(omsInstallType)
    elif(linuxType == 'Oracle'):
       runOracleCommands(omsInstallType)       
    elif(linuxType == 'Ubuntu'):
       runUbuntuCommands(omsInstallType)
    elif(linuxType == 'SLES'):
       runSLESCommands(omsInstallType)
    elif(linuxType == 'Debian'):
       runDebianCommands(omsInstallType)
    else:
       msg='Unsupported Linux OS...Stopping OMS Log Collection...%s' % linuxType
       print(msg)
       writeLogOutput(msg)
       sys.exit(1)

    '''
    Run common OS commands after running omsagent specific commands
    '''
    if(omsInstallType == 1 or omsInstallType == 2):
       runCommonCommands()

    '''
    Run DSC diagnostics commands
    '''
    cmd='chmod +x ./dscDiagnostics.sh'
    out=execCommand(cmd)
    cmd='bash ./dscDiagnostics.sh ' + outDir + '/dscdiagnostics-' + str(datetime.datetime.utcnow().isoformat())
    out=execCommand(cmd)
    writeLogCommand(cmd)
    writeLogOutput(out)

    '''
    Run Update Assessment diagnostics commands
    '''
    print("Starting to check Available Updates")
    cmd=GetUpdates()
    if cmd:
        out=execCommand_always_output(cmd)
        writeLogCommand(cmd)
        writeLogOutput(out)
    else:
        writeLogOutput("unknown package manager on the system")

    print("Completed checking Available Updates")

    '''
    Run Update Management Health Check Script
    '''
    path = outDir + "/updateMgmtlogs"
    versioned_python = "python{0}".format(sys.version_info[0])
    cmd='sudo {0} ./update_mgmt_health_check.py {1}'.format(versioned_python, path)
    out=execCommand(cmd)
    writeLogOutput(out)

    '''
    Logic to capture IOError or OSError in above logic
    '''
except (IOError) as e:
    print(e)
    logging.error('Could not save repo to repofile %s: %s' % (outFile, e))
    sys.exit(2)
except (OSError) as e:
    print(e)
    logging.error('Error occurred in OS command execution %s' % (e))
    sys.exit(2)
except (Exception) as e:
    print(e)
    logging.error('General Exception occurred %s' % (e))
    sys.exit(2)
    
finally:
    '''
    Final logic to close o/p file and create tar ball for sending it to support
    '''
    outFile.close()
    compressOMSLog(outDir, compressFile)
    removeTempFiles()
    print('OMS Linux Agent Log is archived in file : %s' % (compressFile))
    sys.exit()