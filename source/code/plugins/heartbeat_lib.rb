# Copyright (c) Microsoft Corporation. All rights reserved.
module HeartbeatModule
  class LoggingBase
    def log_error(text)
    end
  end

  class RuntimeError < LoggingBase
    def log_error(text)
      $log.error "RuntimeError: #{text}"
    end
  end

  class Heartbeat
    require 'json'
    require_relative 'oms_common'
  
    def initialize(error_handler)
      @error_handler = error_handler
    end

    # match string of the form (1 or more non . chars)- followed by a . - (1 or more non . chars) - followed by anything
    MAJOR_MINOR_VERSION_REGEX = /([^\.]+)\.([^\.]+).*/

    def get_heartbeat_data_item(time, os_conf_file_path, agent_install_conf_file_path)
      record = {}
      record["Timestamp"] = OMS::Common.format_time(time)
      record["Computer"] = OMS::Common.get_hostname

      record["OSType"] = "Linux"
      os_name = OMS::Common.get_os_name(os_conf_file_path)
      record["OSName"] = os_name unless os_name.nil?
      os_version = OMS::Common.get_os_version(os_conf_file_path)
      os_major_version = os_version[MAJOR_MINOR_VERSION_REGEX, 1] unless os_version.nil?
      os_minor_version = os_version[MAJOR_MINOR_VERSION_REGEX, 2] unless os_version.nil?
      record["OSMajorVersion"] = os_major_version unless os_major_version.nil?
      record["OSMinorVersion"] = os_minor_version unless os_minor_version.nil?

      record["Category"] = "Agent"
      record["SCAgentChannel"] = "Direct"

      record["ComputerPrivateIps"] = OMS::Common.get_private_ips

      installed_date = OMS::Common.get_installed_date(agent_install_conf_file_path)
      record["InstalledDate"] = installed_date unless installed_date.nil?
      agent_version = OMS::Common.get_agent_version(agent_install_conf_file_path)
      record["Version"] = agent_version unless agent_version.nil?

      return record
    end

    def enumerate(time, os_conf_file_path = "/etc/opt/microsoft/scx/conf/scx-release", agent_install_conf_file_path = "/etc/opt/microsoft/omsagent/sysconf/installinfo.txt")
      data_item = get_heartbeat_data_item(time, os_conf_file_path, agent_install_conf_file_path)
      wrapper = {
         "DataType"=>"HEALTH_ASSESSMENT_BLOB",
         "IPName"=>"LogManagement",
         "DataItems"=>[data_item]
      }
      return wrapper
    end

  end

end
