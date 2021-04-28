# Copyright (c) Microsoft Corporation. All rights reserved.
require 'test/unit'
require 'tempfile'
require_relative 'omstestlib'
require_relative '../../../source/code/plugins/heartbeat_lib'

class HeartbeatTestRuntimeError < HeartbeatModule::LoggingBase
  def log_error(text)
    raise text
  end
end

class HeartbeatLib_Test < Test::Unit::TestCase
  class << self
    def startup
      @@heartbeat_lib = HeartbeatModule::Heartbeat.new(HeartbeatTestRuntimeError.new)
    end

    def shutdown
      #no op
    end
  end

  def setup
    @tmp_os_conf_file = Tempfile.new('os_conf_file')
    @tmp_agent_install_conf_file = Tempfile.new('agent_install_conf_file')
  end

  def teardown
    tmp_path = @tmp_os_conf_file.path
    assert_equal(true, File.file?(tmp_path))
    @tmp_os_conf_file.unlink
    assert_equal(false, File.file?(tmp_path))
    tmp_path = @tmp_agent_install_conf_file.path
    assert_equal(true, File.file?(tmp_path))
    @tmp_agent_install_conf_file.unlink
    assert_equal(false, File.file?(tmp_path))
  end

  def test_heartbeat_non_existent_conf_files
    heartbeat_data_item = call_get_heartbeat('/etc/nonexistentos.conf', '/etc/nonexistentagentinstall.conf')
    verify_invalid_heartbeat_data(heartbeat_data_item)
  end

  def test_heartbeat_empty_conf_files
    heartbeat_data_item = call_get_heartbeat(@tmp_os_conf_file.path, @tmp_agent_install_conf_file.path)
    verify_invalid_heartbeat_data(heartbeat_data_item)
  end

  def test_heartbeat_malformed_conf_files
    $log = OMS::MockLog.new
    File.write(@tmp_os_conf_file.path, "Malformed OS Name\nMalformed OS Version\n")
    File.write(@tmp_agent_install_conf_file.path, "Agent Version\nInstalledDate\n")
    heartbeat_data_item = call_get_heartbeat(@tmp_os_conf_file.path, @tmp_agent_install_conf_file.path)
    assert_equal(1, $log.logs.size, "Unexpected error logs: #{$log.logs}")
    verify_invalid_heartbeat_data(heartbeat_data_item)
  end

  def test_heartbeat_valid_conf_files
    File.write(@tmp_os_conf_file.path, "OSName=Ubuntu\nOSVersion=14.04\nOSFullName=Ubuntu 14.04 (x86_64)\nOSAlias=UniversalD\nOSManufacturer=Canonical Group Limited\n")
    File.write(@tmp_agent_install_conf_file.path, "1.1.0-124 20160412 Release_Build\n2016-05-24T00:27:55.0Z\n")
    heartbeat_data_item = call_get_heartbeat(@tmp_os_conf_file.path, @tmp_agent_install_conf_file.path)
    assert(heartbeat_data_item.has_key?("Timestamp"))
    assert(heartbeat_data_item.has_key?("Computer"))
    assert(heartbeat_data_item.has_key?("OSType"))
    assert(heartbeat_data_item.has_key?("Category"))
    assert(heartbeat_data_item.has_key?("SCAgentChannel"))
    assert(heartbeat_data_item.has_key?("ComputerPrivateIps"))
    assert_equal("Ubuntu", heartbeat_data_item["OSName"], "OSName does not match")
    assert_equal("14", heartbeat_data_item["OSMajorVersion"], "OSMajorVersion does not match")
    assert_equal("04", heartbeat_data_item["OSMinorVersion"], "OSMinorVersion does not match")
    assert_equal("2016-05-24T00:27:55.0Z", heartbeat_data_item["InstalledDate"], "InstalledDate does not match")
    assert_equal("1.1.0-124", heartbeat_data_item["Version"], "AgentVersion does not match")
  end

  def verify_invalid_heartbeat_data(heartbeat_data_item)
    assert(heartbeat_data_item.has_key?("Timestamp"))
    assert(heartbeat_data_item.has_key?("Computer"))
    assert(heartbeat_data_item.has_key?("OSType"))
    assert(heartbeat_data_item.has_key?("Category"))
    assert(heartbeat_data_item.has_key?("SCAgentChannel"))
    assert(heartbeat_data_item.has_key?("ComputerPrivateIps"))
    assert(heartbeat_data_item.has_key?("Version"))
    assert(!heartbeat_data_item.has_key?("OSName"))
    assert(!heartbeat_data_item.has_key?("OSMajorVersion"))
    assert(!heartbeat_data_item.has_key?("OSMinorVersion"))
    assert(!heartbeat_data_item.has_key?("InstalledDate"))
  end

  # wrapper to call get heartbeat
  def call_get_heartbeat(os_conf_file_path, agent_install_conf_file_path)
    @@heartbeat_lib.get_heartbeat_data_item(Time.now, os_conf_file_path, agent_install_conf_file_path)
  end
end

