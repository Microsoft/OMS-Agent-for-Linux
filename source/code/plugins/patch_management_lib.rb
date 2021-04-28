require 'rexml/document'
require 'cgi'
require 'digest'
require 'set'
require 'securerandom'

require_relative 'oms_common'
require_relative 'oms_configuration'
require_relative 'omslog'

class LinuxUpdates

    @@prev_hash = ""
    @@delimiter = "_"
    @@force_send_last_upload = Time.now
    @@os_details = nil

    MAJOR_MINOR_VERSION_REGEX = /([^\.]+)\.([^\.]+).*/
    OMS_ADMIN_FILE = "/etc/opt/microsoft/omsagent/conf/omsadmin.conf"
    SCX_RELEASE_FILE = "/etc/opt/microsoft/scx/conf/scx-release"
    SCHEDULE_NAME_VARIABLE = "SCHEDULE_NAME"
    APT_GET_START_DATE_TIME_FORMAT = "%Y-%m-%d %H:%M:%S"

    def initialize(log)
        @log = log
     end

    def getAgentId()
        return OMS::Configuration.agent_id
    end

    def getHostOSDetails()
        if(@@os_details.nil?)    
           if File.exist?(SCX_RELEASE_FILE) # If file exists
            File.open(SCX_RELEASE_FILE, "r") do |f| # Open file
			@@os_details={}
                f.each_line do |line|       # Split each line and
                    line.split(/\r?\n/).reject{ |l|  # reject all those line
                        !l.include? "=" }.map! {|s|    # which do not
                            s.split("=")}.map! {|key, value| # have "="; split
                                @@os_details[key] = value     # by "=" and add to ret.
                        }
                end
            end
            else
                @log.debug "Could not find the file #{SCX_RELEASE_FILE}"
                @@os_details = {}
            end
        end

        return @@os_details
    end

    # This temporary fix is for version management for cache lookup.                        
    def getOSShortName(os_short_name = nil, os_version=nil)
        version = ""
        hostOSDetailsMap = getHostOSDetails()
	  #os short name is not proper for oracle linux at /etc/opt/microsoft/scx/conf/scx-release. this is to return proper short name till scx fixes the issue.
	  if hostOSDetailsMap.key?("OSFullName") && hostOSDetailsMap.key?("OSShortName")
			osFullName = hostOSDetailsMap["OSFullName"]
			osShortName = hostOSDetailsMap["OSShortName"]
			if osFullName.downcase.include?("oracle") && ! osShortName.downcase.include?("oracle")
				os_short_name = "Oracle"
			end
	  end

        # match string of the form (1 or more non . chars)- followed by a . - (1 or more non . chars) - followed by anything
        if hostOSDetailsMap.key?("OSShortName")
            osName = (os_short_name.nil?) ? hostOSDetailsMap["OSShortName"].split("_")[0] : os_short_name.split("_")[0]
        else
            osName =  (os_short_name.nil?) ? hostOSDetailsMap["OSFullName"] : os_short_name.split("_")[0]
        end

        if (os_version.nil?)
            @os_major_version = hostOSDetailsMap["OSVersion"][MAJOR_MINOR_VERSION_REGEX, 1] unless hostOSDetailsMap["OSVersion"].nil?
            @os_minor_version = hostOSDetailsMap["OSVersion"][MAJOR_MINOR_VERSION_REGEX, 2] unless hostOSDetailsMap["OSVersion"].nil?
            @default_version = hostOSDetailsMap["OSVersion"]
        else
            @os_major_version = os_version[MAJOR_MINOR_VERSION_REGEX, 1] unless os_version.nil?
            @os_minor_version = os_version[MAJOR_MINOR_VERSION_REGEX, 2] unless os_version.nil?
            @default_version = os_version
        end 
        
        case osName
        when "Ubuntu"
            if @os_major_version == "12" || @os_major_version == "13"
                version = "12.04"
            elsif  @os_major_version == "14" || @os_major_version == "15"
                version = "14.04"
            elsif  @os_major_version == "16" || @os_major_version == "17"
                version = "16.04"
            else
                version = @default_version
            end
        when "CentOS"
            if @os_major_version == "5"
                version = "5.0" 
            elsif  @os_major_version == "6"
                version = "6.0"
            elsif  @os_major_version == "7"
                version = "7.0"
            elsif  @os_major_version == "8"
                version = "8.0"
            else
                version = @default_version
            end
        when "RHEL"
            if @os_major_version == "5"
                version = "5.0" 
            elsif  @os_major_version == "6"
                version = "6.0"
            elsif  @os_major_version == "7"
                version = "7.0"
            elsif  @os_major_version == "8"
                version = "8.0"
            else
                version = @default_version
            end
	  when "Oracle"
		   version = "6.0"
        when "SUSE"
            if @os_major_version == "11"
                version = "11.0" 
            elsif  @os_major_version == "12"
                version = "12.0"
            elsif  @os_major_version == "15"
                version = "15.0"
            else
                version = @default_version
            end
        else
            version = @default_version
        end

        return osName + @@delimiter + version
    end

    def self.prev_hash= (value)
        @@prev_hash = value
    end

    def isInstalledPackageInstanceXML(instanceXML)
        instanceXML.attributes["CLASSNAME"] == "MSFT_nxPackageResource"
    end

    def isAvailableUpdateInstanceXML(instanceXML)
        instanceXML.attributes["CLASSNAME"] == "MSFT_nxAvailableUpdatesResource"
    end

    def instanceXMLtoHash(instanceXML)
        ret = {}
        propertyXPath = "PROPERTY"
        instanceXML.elements.each(propertyXPath) { |inst| #AnonFunc in rb.
            name = inst.attributes['NAME']
            rexmlText = REXML::XPath.first(inst, 'VALUE').get_text # TODO escape unicode chars like "&amp;"
            value = rexmlText ? rexmlText.value.strip : ''
            ret[name] = value
        }
        ret
    end

    def availableUpdatesXMLtoHash(availableUpdatesXML, os_short_name)
        availableUpdatesHash = instanceXMLtoHash(availableUpdatesXML)
        ret = {}
        ret["CollectionName"] = availableUpdatesHash["Name"] + @@delimiter + 
                                availableUpdatesHash["Version"] + @@delimiter + os_short_name
        ret["PackageName"] = availableUpdatesHash["Name"]
        ret["Architecture"] = availableUpdatesHash.key?("Architecture") ? availableUpdatesHash["Architecture"] : nil
        ret["PackageVersion"] = availableUpdatesHash["Version"]
        ret["Repository"] = availableUpdatesHash.key?("Repository") ? availableUpdatesHash["Repository"] : nil
        ret["Installed"] = false
        ret["UpdateState"] = "Needed"
        if (Integer(availableUpdatesHash["BuildDate"]) rescue false)
            ret["Timestamp"] = OMS::Common.format_time(availableUpdatesHash["BuildDate"].to_i)
        end
        ret
    end

    def availableHeartbeatItem()        
        ret = {}
        ret["CollectionName"] = "HeartbeatData" + @@delimiter + 
                                "0.0.UpdateManagement.0"+ @@delimiter + "Heartbeat"
        ret["PackageName"] = "UpdateManagementHeartbeat"
        ret["Architecture"] = "all"
        ret["PackageVersion"] = nil
        ret["Repository"] = nil
        ret["Installed"] = false
        ret["UpdateState"] = "NotNeeded"        
        ret
    end

    def installedPackageXMLtoHash(packageXML, os_short_name)
        packageHash = instanceXMLtoHash(packageXML)
        ret = {}
        
        ret["CollectionName"] = packageHash["Name"] + @@delimiter + 
                                packageHash["Version"] + @@delimiter + os_short_name
        ret["PackageName"] = packageHash["Name"]
        ret["Architecture"] = packageHash.key?("Architecture") ? packageHash["Architecture"] : nil
        ret["PackageVersion"] = packageHash["Version"]  
        ret["Size"] = packageHash["Size"]
        ret["Repository"] = packageHash.key?("Repository") ? packageHash["Repository"] : nil
        ret["Installed"] = true
        ret["UpdateState"] = "NotNeeded"
        if (Integer(packageHash["InstalledOn"]) rescue false)
            ret["Timestamp"] = OMS::Common.format_time(packageHash["InstalledOn"].to_i)
        end
        ret
    end

    def strToXML(xml_string)
        xml_unescaped_string = CGI::unescapeHTML(xml_string)
        REXML::Document.new xml_unescaped_string
    end

    # Returns an array of xml instances (all types)
    def getInstancesXML(inventoryXML)
        instances = []
        xpathFilter = "INSTANCE/PROPERTY.ARRAY/VALUE.ARRAY/VALUE/INSTANCE"
        inventoryXML.elements.each(xpathFilter) { |inst| instances << inst }
        instances
    end

    def removeDuplicateCollectionNames(data_items)
        collection_names = Set.new
        data_items.select { |data_item|
            collection_names.add?(data_item["CollectionName"]) && true || false
        }
    end

    def transform_and_wrap(
        inventoryXMLstr, 
        host, 
        time, 
        force_send_run_interval = 86400,
        osNameParam = nil, 
        osFullNameParam = nil,
        osVersionParam = nil, 
        osShortNameParam = nil)

        agentId = getAgentId()
        hostOSDetailsMap = getHostOSDetails()
       
        # Taking the parameters - Helps in mocking, in the case of tests.
        osName =  (osNameParam == nil) ? hostOSDetailsMap["OSName"] : osNameParam
        osVersion = (osVersionParam == nil) ? hostOSDetailsMap["OSVersion"] : osVersionParam
        osFullName = (osFullNameParam == nil) ? hostOSDetailsMap["OSFullName"] : osFullNameParam
        osShortName = getOSShortName(osShortNameParam, osVersion)

        # Do not send duplicate data if we are not forced to
        hash = Digest::SHA256.hexdigest(inventoryXMLstr)
        @log.debug "LinuxUpdates : Sending available updates information data. Hash=#{hash[0..5]}"

        # Extract the instances in xml format
        inventoryXML = strToXML(inventoryXMLstr)
        instancesXML = getInstancesXML(inventoryXML)

        # Split installedPackages from services 
        installedPackagesXML = instancesXML.select { |instanceXML| isInstalledPackageInstanceXML(instanceXML) }
        availableUpdatesXML = instancesXML.select { |instanceXML| isAvailableUpdateInstanceXML(instanceXML) }

        # Convert to xml to hash/json representation
        installedPackages = installedPackagesXML.map! { |installedPackage|  installedPackageXMLtoHash(installedPackage, osShortName)}
        availableUpdates = availableUpdatesXML.map! { |availableUpdate|  availableUpdatesXMLtoHash(availableUpdate, osShortName)}

        # Remove duplicate services because duplicate CollectionNames are not supported. TODO implement ordinal solution
        installedPackages = removeDuplicateCollectionNames(installedPackages)
        availableUpdates = removeDuplicateCollectionNames(availableUpdates)
        #Today the agent doesn't send any data if the machine is not missing any available updates. 
        #This leads to uncertainty whether the machine is really up to date or it is not sending data eventhough updates are missing. 
        #with this change,the agent will send heartbeat item whether the machine is missing updates or not.     
        heartbeatItem = availableHeartbeatItem()
        collections = [heartbeatItem]
        
        if (installedPackages.size > 0)
            collections += installedPackages
        end
        
        if  (availableUpdates.size > 0)
            collections += availableUpdates
        end

        timestamp = OMS::Common.format_time(time)
        wrapper = {
            "DataType"=>"LINUX_UPDATES_SNAPSHOT_BLOB",
            "IPName"=>"Updates",
            "DataItems"=>[{
                    "Timestamp" => timestamp,
                    "Host" => host,
                    "AgentId" => agentId,
                    "OSType" => "Linux",
                    "OSName" => osName,
                    "OSVersion" => osVersion,
                    "OSFullName" => osFullName,
                    "Collections"=> collections
                }]}
          @log.debug "LinuxUpdates : installedPackages x #{installedPackages.size}, 
                                        availableUpdates x #{availableUpdates.size}"
          return wrapper
    end
	
end