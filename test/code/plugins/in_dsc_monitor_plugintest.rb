require 'fluent/test'
require_relative '../../../source/code/plugins/in_dsc_monitor'
require 'flexmock/test_unit'

class DscMonitorTest < Test::Unit::TestCase
  include FlexMock::TestCase

  TMP_DIR = File.dirname(__FILE__) + "/../tmp/test_dscmonitor"
  CHECK_IF_DPKG = "which dpkg > /dev/null 2>&1; echo $?" 
  CHECK_DSC_INSTALL = "dpkg --list omsconfig > /dev/null 2>&1; echo $?"
  CHECK_DSC_STATUS = "/opt/microsoft/omsconfig/Scripts/TestDscConfiguration.py"
  CHECK_DSC_STATUS_PYTHON_3 = "/opt/microsoft/omsconfig/Scripts/python3/TestDscConfiguration.py"
  CHECK_PYTHON = "which python2"

  def setup
    Fluent::Test.setup
    FileUtils.mkdir_p(TMP_DIR)
  end

  def teardown
    super
    if TMP_DIR
      FileUtils.rm_rf(TMP_DIR)
    end
    Fluent::Engine.stop
  end

  CONFIG = %[
    tag oms.mock.dsc 
    check_install_interval 2 
    check_status_interval 2
    dsc_cache_file #{TMP_DIR}/cache.yml
  ]

  def create_driver(conf=CONFIG)
    Fluent::Test::InputTestDriver.new(Fluent::DscMonitoringInput).configure(conf)
  end

  def test_dsc_install_failure_message
    dsc_install_fail_message = "omsconfig is not installed, OMS Portal \
configuration will not be applied and solutions such as Change Tracking and Update Assessment will \
not function properly. omsconfig can be installed by rerunning the omsagent installation" 

    flexmock(Fluent::DscMonitoringInput).new_instances do |instance|
      instance.should_receive(:`).with(CHECK_IF_DPKG).and_return(0)
      instance.should_receive(:`).with(CHECK_DSC_INSTALL).and_return(1)
    end

    d = create_driver
    d.run
    emits = d.emits

    assert_equal(true, emits.length > 0)
    assert_equal("oms.mock.dsc", emits[0][0])
    assert_instance_of(Float, emits[0][1])
    assert_equal(dsc_install_fail_message, emits[0][2]["message"])
  end

  def test_dsc_check_failure_message
    dsc_statuscheck_fail_message = "Two successive configuration applications from \
OMS Settings failed – please report issue to github.com/Microsoft/PowerShell-DSC-for-Linux/issues"

    flexmock(Fluent::DscMonitoringInput).new_instances do |instance|
      instance.should_receive(:`).with(CHECK_IF_DPKG).and_return(0)
      instance.should_receive(:`).with(CHECK_DSC_INSTALL).and_return(0)
      instance.should_receive(:`).with(CHECK_DSC_STATUS).and_return("Mock DSC config check")
      instance.should_receive(:`).with(CHECK_DSC_STATUS_PYTHON_3).and_return("Mock DSC config check")
      instance.should_receive(:`).with(CHECK_PYTHON).and_return("/usr/bin/python2") # as if python2 is installed
    end

    d = create_driver
    d.run(num_waits = 90)
    emits = d.emits

    assert_equal(true, emits.length > 0)
    assert_equal("oms.mock.dsc", emits[0][0])
    assert_instance_of(Float, emits[0][1])
    assert_equal(dsc_statuscheck_fail_message, emits[0][2]["message"])
  end


  def test_dsc_check_success_emits_no_messages
    result =
      'Operation TestConfiguration completed successfully.
      {
      "InDesiredState": true,
      "ResourceId": []
      }'

    flexmock(Fluent::DscMonitoringInput).new_instances do |instance|
      instance.should_receive(:`).with(CHECK_IF_DPKG).and_return(0)
      instance.should_receive(:`).with(CHECK_DSC_INSTALL).and_return(0)
      instance.should_receive(:`).with(CHECK_DSC_STATUS).and_return(result)
      instance.should_receive(:`).with(CHECK_DSC_STATUS_PYTHON_3).and_return(result)
      instance.should_receive(:`).with(CHECK_PYTHON).and_return("/usr/bin/python2") # as if python2 is installed
    end

    d = create_driver
    d.run(num_waits = 90)
    emits = d.emits

    assert_equal(0, emits.length)
  end

end
