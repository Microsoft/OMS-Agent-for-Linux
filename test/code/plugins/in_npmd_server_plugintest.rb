require 'fluent/test'
require_relative '../../../source/code/plugins/in_npmd_server'
require_relative '../../../source/code/plugins/oms_diag_lib'
require 'socket'
require 'securerandom'

class Logger
    def self.logToStdOut(msg, depth=0)
        #puts msg
    end
    class << self
        alias_method :logError, :logToStdOut
        alias_method :logInfo,  :logToStdOut
        alias_method :logWarn,  :logToStdOut
    end
end


class NPMDServerTest < Test::Unit::TestCase
    class OMS::Diag
        @@DiagSupported = true
    end

    TMP_DIR = "tmp_npmd_test"
    FAKE_ADMIN_CONF_LOCATION = "#{TMP_DIR}/omsadmin.conf"
    FAKE_ADMIN_CONF_FILE_DATA = 'AGENT_GUID=abcde_test_guid'
    FAKE_BINARY_BASENAME = "fake_npmd_binary.rb"
    FAKE_BINARY_FILENAME = File.dirname(__FILE__) + "/#{FAKE_BINARY_BASENAME}"
    RUBY_BINARY_LOCATION = "ruby"
    FAKE_BINARY_INVOCATION = "#{RUBY_BINARY_LOCATION} #{TMP_DIR}/#{FAKE_BINARY_BASENAME}"
    FAKE_BINARY_LOCATION = "#{TMP_DIR}/#{FAKE_BINARY_BASENAME}"
    FAKE_UUID_LOCATION = "#{TMP_DIR}/fake_agent_uuid.txt"
    FAKE_AGENT_ID = "NPMD-FAKE-AGENT-ID"
    FAKE_UNIX_ENDPOINT = "#{TMP_DIR}/test_agent.sock"
    TEST_CONTROL_DATA_FILE = "#{TMP_DIR}/test_agent_config.xml"

    CMD_ENUMERATE_BINARY_INSTANCES = "ps aux | grep fake_npmd"

    CMD_START_NPMD  = Fluent::NPM::CMD_START
    CMD_STOP_NPMD   = Fluent::NPM::CMD_STOP
    CMD_CONFIG_NPMD = Fluent::NPM::CMD_CONFIG
    CMD_PURGE_NPMD  = Fluent::NPM::CMD_PURGE
    CMD_LOG_NPMD    = Fluent::NPM::CMD_LOG

    STALE_AGENT_COUNT = 4
    ONE_MIN_IN_MSEC = 6000
    ONE_MSEC        = 0.01

    CONTROL_DATA = '<?xml version="1.0" encoding="utf-16"?><Configuration xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" Version="3"><NetworkMonitoringAgentConfigurationV3><Metadata>{"Version":3,"Protocol":1,"SubnetUid":1,"AgentUid":1}</Metadata><NetworkNameToNetworkMap>{"Default":{"Subnets":["1","2"]}, "NewOne":{"Subnets":["3"]}}</NetworkNameToNetworkMap><SubnetIdToSubnetMap>{"1":"65.171.0.0/16", "2":"198.165.0.0/21", "3":"162.128.0.0/21"}</SubnetIdToSubnetMap><AgentFqdnToAgentMap>{"1":{"IPs":[{"Value":"65.171.126.72","Subnet":"1"}, {"Value":"65.171.126.73","Subnet":"1"}],"Protocol":"1"}, "2":{"IPs":[{"Value":"65.271.126.72","Subnet":"2"}],"Protocol":"1"}}</AgentFqdnToAgentMap><RuleNameToRuleMap>{"Default":{"ActOn":[{"SN":"*","SS":"*","DN":"*","DS":"*"}],"Threshold":{"Loss":-1.0,"Latency":-1.0},"Exceptions":[],"Protocol":1}}</RuleNameToRuleMap></NetworkMonitoringAgentConfigurationV3></Configuration>'

    TEST_ERROR_LOG_EMIT = "This is a test error log"
    TEST_ERROR_LOG_BINARY_ABSENT = "Binary not found at given location"
    TEST_ERROR_LOG_BINARY_DUPLICATE = "Found both x64 and x32 staging binaries"
    TEST_ERROR_LOG_STDERROR = "NPMDTest wrote this error log"
    TEST_ERROR_LOG_INVALID_USER = "Invalid user:"
    TEST_ERROR_LOG_CAP_NOT_SUPPORTED = "Distro has no support for filesystem capabilities"

    def setup
        Fluent::Test.setup
        FileUtils.mkdir_p(TMP_DIR)
        FileUtils.cp(FAKE_BINARY_FILENAME, "#{TMP_DIR}/#{FAKE_BINARY_BASENAME}")
        f = File.new(TEST_CONTROL_DATA_FILE, "w")
        f.write(CONTROL_DATA)
        f.close
        f = File.new(FAKE_ADMIN_CONF_LOCATION, "w")
        f.write(FAKE_ADMIN_CONF_FILE_DATA)
        f.close
        Fluent::NPM::OMS_AGENTGUID_FILE.replace "#{TMP_DIR}/test_oms_guid_file"
    end

    def teardown
        super
        Fluent::Engine.stop
        FileUtils.rm_rf(TMP_DIR)
    end

    CONFIG = %[
        type npmd
        omsadmin_conf_path     #{FAKE_ADMIN_CONF_LOCATION}
        location_unix_endpoint #{FAKE_UNIX_ENDPOINT}
        location_control_data  #{TEST_CONTROL_DATA_FILE}
        location_agent_binary  #{FAKE_BINARY_LOCATION}
        tag oms.mock.npmd
    ]

    def create_driver(conf=CONFIG)
        _d = Fluent::Test::InputTestDriver.new(Fluent::NPM).configure(conf)
        _d.instance.binary_presence_test_string = "fake_npmd"
        _d.instance.binary_invocation_cmd = FAKE_BINARY_INVOCATION
        _d.instance.num_path_data = 0
        _d.instance.num_agent_data = 0
        _d.instance.num_config_sent = 0
        _d.instance.is_purged = false
        _d.instance.omsagentUID = Process.euid
        _d.instance.do_capability_check = false
        _d.instance.dsc_resource_version = "TEST"
        _d
    end

    def create_multiple_test_binary_instances
        (1..STALE_AGENT_COUNT).each do
            _id = Process.spawn(FAKE_BINARY_INVOCATION)
            # puts "Creating fake process with id #{_id}"
            Process.detach(_id)
        end
    end

    def get_num_test_binary_instances
        _resultStr = `#{CMD_ENUMERATE_BINARY_INSTANCES.chomp}`
        _lines = _resultStr.split("\n")
        _count = 0
        _lines.each do |line|
            _userName = line.split()[0]
            if line.include?FAKE_BINARY_BASENAME
                _uId = -1

                # Case when _userName is the uid itself
                _uId = _userName.to_i if /\A\d+\z/.match(_userName.chomp)

                # Get uid from _userName if _userName is -1
                begin
                    _uId = Process::UID.from_name(_userName) if (_uId == -1)
                rescue ArgumentError
                    raise "Got Argumenterror when looking for username:#{_userName} in line #{line}"
                end

                _count += 1 if (_uId == Process.uid)
            end
        end
        _count
    end

    def parse_diag_logs_from_emits(emits)
        error_logs = nil
        assert(emits.length > 0, "At least some data should have been emitted by now")
        emits.each do |x|
            if x.last.key?(OMS::Diag::DI_KEY_LOGMESSAGE)
                error_logs ||= []
                error_logs << x.last[OMS::Diag::DI_KEY_LOGMESSAGE]
            end
        end
        error_logs
    end

    def check_presence_of_error_log(error_logs, test_log)
        found_test_log = false
        unless error_logs.nil?
            assert(error_logs.is_a?(Array), "Error logs should be an array")
            error_logs.each do |x|
                if x == test_log
                    found_test_log = true
                    break
                end
            end
        end
        found_test_log
    end

    def check_presence_of_error_log_beginning_with(error_logs, test_prefix)
        found_test_log = false
        unless error_logs.nil?
            assert(error_logs.is_a?(Array), "Error logs should be an array")
            error_logs.each do |x|
                if x.start_with?(test_prefix)
                    found_test_log = true
                    break
                end
            end
        end
        found_test_log
    end

    # Test01: Check if multiple stale instances are getting killed or not
    # Sequence:
    # 1. Create fake UNIX socket for multiple instances to latch onto
    # 2. Create multiple fake binary instances and assert if running
    # 3. Register run post condition as:
    #   (a) Wait for npmdClientSock to be non nil
    #   (b) Assert only one instance of fake binary is running
    # 4. Run the driver
    # 5. Assert that there are no fake binary instances running
    # 6. Assert that npmdClientSock is nil again
    def test_case_01_multiple_stale_instance_deletion
        # Step 1
        File.unlink(FAKE_UNIX_ENDPOINT) if File.exist?FAKE_UNIX_ENDPOINT
        UNIXServer.new(FAKE_UNIX_ENDPOINT)

        # Step 2
        create_multiple_test_binary_instances()
        assert(STALE_AGENT_COUNT <= get_num_test_binary_instances(), "Could not create #{STALE_AGENT_COUNT} instances")

        # Step 3
        d = create_driver
        d.register_run_post_condition {
            (1..ONE_MIN_IN_MSEC).each do
                sleep(ONE_MSEC) if d.instance.npmdClientSock.nil?
            end
            assert(!d.instance.npmdClientSock.nil?, "NPMD client sock should have been non nil")

            assert_equal(1, get_num_test_binary_instances(), "Multiple instance found when only 1 should be running")
            true
        }

        # Step 4
        d.run

        # Step 5
        assert_equal(0, get_num_test_binary_instances(), "No instance of fake binary should be running")

        # Step 6
        assert(d.instance.npmdClientSock.nil?, "npmdClientSock should be nil as all clients are stopped")
    end

    # Test02: Check if emit is working properly
    # Sequence:
    # 1. Register run post condition as:
    #   (a) Wait for emitted data has both path data and agent data
    # 2. Run the driver
    # 3. Assert that path data has Computer key
    # 4. Assert that agent data has AgentId key
    def test_case_02_emit_path_agent_data
        # Step 1
        d = create_driver
        d.register_run_post_condition {
            (1..ONE_MIN_IN_MSEC).each do
                sleep(ONE_MSEC) unless (d.instance.num_path_data > 0 and d.instance.num_agent_data > 0)
            end

            assert(d.instance.num_path_data > 0, "Num path data should be greater than 0")
            assert(d.instance.num_agent_data > 0, "Num agent data should be greater than 0")
            true
        }

        # Step 2
        d.run
        emits = d.emits
        assert(emits.length > 0, "There should be at least 1 emitted item by now")
        path_data = nil
        agent_data = nil
        emits.each do |x|
            if x.last.key?("DataItems")
                x.last["DataItems"].each do |z|
                    if z.key?("SubType")
                        if z["SubType"] == "NetworkPath"
                            path_data ||= []
                            path_data << z
                        elsif z["SubType"] == "NetworkAgent"
                            agent_data ||= []
                            agent_data << z
                        end
                    end
                end
            end
        end

        # Step 3
        #assert(!path_data.nil?, "Path data should not be nil")
        #assert(path_data.length > 0, "There should be at least 1 path data element")
        #path_data.each do |x|
        #    assert(x.key?("Computer"), "All path data elements should have Computer key appended")
        #end

        # Step 4
        #assert(!agent_data.nil?, "Agent data should not be nil")
        #assert(agent_data.length > 0, "There should be at least 1 agent data element")
        #agent_data.each do |x|
            #assert(x.key?("AgentId"), "All agent data elements should have AgentId key appended")
        #end
    end

=begin
    # Test03: Check if configuration was sent from startup
    # Sequence:
    # 1. Assert num_config_sent as 0
    # 2. Register run post condition as:
    #   (a) Wait for npmdClientSock to be non nil
    #   (b) Wait for 1 second post this
    # 3. Run the driver
    # 4. Assert num_config_sent to be non zero
    def test_case_03_check_if_config_sent_from_startup
        # Step 1
        d = create_driver
        assert_equal(0, d.instance.num_config_sent, "There should not be any config sent before run")

        # Step 2
        d.register_run_post_condition {
            (1..ONE_MIN_IN_MSEC).each do
                sleep(ONE_MSEC) if d.instance.npmdClientSock.nil?
            end
            assert(!d.instance.npmdClientSock.nil?, "NPMD client sock should have been non nil")
            sleep(100 * ONE_MSEC)
            true
        }

        # Step 3
        d.run

        # Step 4
        assert(d.instance.num_config_sent > 0, "There should have been atleast one config sent to agent")
    end
=end

    # Test04: Check if configuration is sent via cmd
    # Sequence:
    # 1. Register run post condition as:
    #   (a) Wait for npmdClientSock to be non nil
    #   (b) Note value of num_config_sent
    #   (c) Send config cmd over socket
    # 2. Run the driver
    # 3. Assert increase in num_config_sent
    def test_case_04_check_config_sent_from_cmd
        # Step 1
        d = create_driver
        num_conf_sent = -1
        d.register_run_post_condition {
            (1..ONE_MIN_IN_MSEC).each do
                sleep(ONE_MSEC) if d.instance.npmdClientSock.nil?
            end
            assert(!d.instance.npmdClientSock.nil?, "NPMD Client sock should have been non nil")

            sleep(100 * ONE_MSEC)

            num_conf_sent = d.instance.num_config_sent
            assert(num_conf_sent > 0, "There should some config sent by now")

            d.instance.process_dsc_command(CMD_CONFIG_NPMD)

            sleep(100 * ONE_MSEC)
            true
        }

        # Step 3
        d.run

        # Step 4
        assert(d.instance.num_config_sent > num_conf_sent, "There should have been at least one more config sent to agent from before")
    end

    # Test05: Check if error log is emitting
    # Sequence:
    # 1. Register run post condition as:
    #   (a) Wait for emit to have error log with "Test" Key
    # 2. Run the driver
    # 3. Assert Test key value in emit is equal to custom log sent
    def test_case_05_error_log_emit
        # Step 1
        d = create_driver
        d.register_run_post_condition {
            sleep(100 * ONE_MSEC)

            d.instance.process_dsc_command("#{CMD_LOG_NPMD}:#{TEST_ERROR_LOG_EMIT}")

            sleep(100 * ONE_MSEC)
            true
        }

        # Step 2
        d.run
        error_logs = parse_diag_logs_from_emits(d.emits)

        # Step 3
        found_sent_log = check_presence_of_error_log(error_logs, TEST_ERROR_LOG_EMIT)
        assert(found_sent_log, "Sent log in test should have been seen");
    end

    # Test06: Check if purge is working
    # Sequence:
    # 1. Register run post condition as:
    #   (a) Wait for npmdClientSock to be non nil
    #   (b) Send purge command
    #   (c) Wait for npmdClientSock to be nil
    #   (d) Wait for is_purged to be true
    # 2. Run the driver
    # 3. Assert no instance of fake binary running
    # 4. Assert file fake binary does not exist
    # 5. Assert file unix endpoint does not exist
    # 6. Assert uuid file does not exist
    def test_case_06_verify_purge
        # Step 1
        d = create_driver
        d.register_run_post_condition {
            (1..ONE_MIN_IN_MSEC).each do
                sleep(ONE_MSEC) if d.instance.npmdClientSock.nil?
            end
            assert(!d.instance.npmdClientSock.nil?, "NPMD client socket should be non nil")

            d.instance.process_dsc_command(CMD_PURGE_NPMD)
            (1..ONE_MIN_IN_MSEC).each do
                sleep(ONE_MSEC) unless d.instance.npmdClientSock.nil?
            end
            assert(d.instance.npmdClientSock.nil?, "NPMD client socket should be nil")

            (1..ONE_MIN_IN_MSEC).each do
                sleep(ONE_MSEC) unless d.instance.is_purged
            end
            assert(d.instance.is_purged, "NPMD client socket should be nil")
            true
        }

        # Step 2
        d.run

        # Step 3
        assert_equal(0, get_num_test_binary_instances(), "No instance of fake binary should be running")

        # Step 4
        assert_equal(false, File.exist?(FAKE_BINARY_LOCATION), "File #{FAKE_BINARY_LOCATION} of binary should not exist")

        # Step 5
        assert_equal(false, File.exist?(FAKE_UNIX_ENDPOINT), "File #{FAKE_UNIX_ENDPOINT} representing endpoint should be deleted")

        # Step 6
        assert_equal(false, File.exist?(FAKE_UUID_LOCATION), "File #{FAKE_UUID_LOCATION} should have been deleted")
    end

    # Test09: Check that binary not found is handled properly
    # Sequence:
    # 1. Delete the binary file and any staging _x32/_x64 binaries
    # 2. Register run post condition as:
    #   (a) Wait for emit to have at least one error log
    # 3. Run the driver
    # 4. Assert that binary not found error is there in error log
    # def test_case_09_binary_not_present
    #     # Step 1
    #     File.unlink(FAKE_BINARY_LOCATION) if File.exist?(FAKE_BINARY_LOCATION)
    #     File.unlink("#{FAKE_BINARY_LOCATION}_x32") if File.exist?("#{FAKE_BINARY_LOCATION}_x32")
    #     File.unlink("#{FAKE_BINARY_LOCATION}_x64") if File.exist?("#{FAKE_BINARY_LOCATION}_x64")

    #     # Step 2
    #     d = create_driver
    #     d.register_run_post_condition {
    #         sleep(100 * ONE_MSEC)
    #         true
    #     }

    #     # Step 3
    #     d.run
    #     error_logs = parse_diag_logs_from_emits(d.emits)

    #     # Step 4
    #     found_binary_absent_log = check_presence_of_error_log(error_logs, TEST_ERROR_LOG_BINARY_ABSENT)
    #     assert_equal(true, found_binary_absent_log, "Binary absent log in test should have been seen");
    # end

    # Test10: Check that binary is getting replaced properly by "_x32"
    # Sequence:
    # 1. Copy the binary file by appending "_x32" to name
    # 2. Store the modification time of copy as mtime_x32_1
    # 3. Delete the binary file
    # 4. Run the driver after a wait
    # 5. Assert that copy with "_x32" ending does not exist
    # 6. Assert that binary file now exists
    # 7. Assert that modificiation time of binary file is equal to mtime_x32_1
    # 8. Copy the binary file by appending "_x32" to name again
    # 9. Store the modification time of binary file as mtime_bin_1
    # 10.Run the driver after a wait
    # 11.Assert that copy with "_x32" ending does not exist
    # 12.Assert that the binary file exists
    # 13.Assert that modification time of binary file is newer than mtime_bin_1
    # def test_case_10_binary_replaced_by_x32
    #     # Step 1
    #     FileUtils.cp(FAKE_BINARY_LOCATION, "#{FAKE_BINARY_LOCATION}_x32") if File.exist?(FAKE_BINARY_LOCATION)

    #     # Step 2
    #     mtime_x32_1 = File.mtime("#{FAKE_BINARY_LOCATION}_x32")

    #     # Step 3
    #     FileUtils.rm(FAKE_BINARY_LOCATION)
    #     assert_equal(false, File.exist?(FAKE_BINARY_LOCATION), "Fake binary file should have been deleted")

    #     # Step 4
    #     sleep(2)
    #     d = create_driver
    #     d.run

    #     # Step 5
    #     assert_equal(false, File.exist?("#{FAKE_BINARY_LOCATION}_x32"), "#{FAKE_BINARY_LOCATION}_x32 should have been deleted")

    #     # Step 6
    #     assert_equal(true, File.exist?(FAKE_BINARY_LOCATION), "Fake binary file should have been created")

    #     # Step 7
    #     mtime_bin = File.mtime(FAKE_BINARY_LOCATION)
    #     assert(mtime_bin == mtime_x32_1, "The new binary should have a time of modification that is equal to x32 one")

    #     # Step 8
    #     FileUtils.cp(FAKE_BINARY_LOCATION, "#{FAKE_BINARY_LOCATION}_x32") if File.exist?(FAKE_BINARY_LOCATION)

    #     # Step 9
    #     mtime_bin_1 = File.mtime(FAKE_BINARY_LOCATION)

    #     # Step 10
    #     sleep(2)
    #     d.run

    #     # Step 11
    #     assert_equal(false, File.exist?("#{FAKE_BINARY_LOCATION}_x32"), "#{FAKE_BINARY_LOCATION}_x32 should have been deleted again")

    #     # Step 12
    #     assert_equal(true, File.exist?(FAKE_BINARY_LOCATION), "Fake binary file should have been created again")

    #     # Step 13
    #     mtime_bin_2 = File.mtime(FAKE_BINARY_LOCATION)
    #     assert(mtime_bin_2 > mtime_bin_1, "The new binary should have a modification that is newer or higher than earlier")
    # end

    # Test11: Check that binary is getting replaced properly by "_x64"
    # Sequence:
    # 1. Copy the binary file by appending "_x64" to name
    # 2. Store the modification time of copy as mtime_x64_1
    # 3. Delete the binary file
    # 4. Run the driver after a wait
    # 5. Assert that copy with "_x64" ending does not exist
    # 6. Assert that binary file now exists
    # 7. Assert that modificiation time of binary file is equal to mtime_x64_1
    # 8. Copy the binary file by appending "_x64" to name again
    # 9. Store the modification time of binary file as mtime_bin_1
    # 10.Run the driver after a wait
    # 11.Assert that copy with "_x64" ending does not exist
    # 12.Assert that the binary file exists
    # 13.Assert that modification time of binary file is newer than mtime_bin_1
    # def test_case_11_binary_replaced_by_x64
    #     # Step 1
    #     FileUtils.cp(FAKE_BINARY_LOCATION, "#{FAKE_BINARY_LOCATION}_x64") if File.exist?(FAKE_BINARY_LOCATION)

    #     # Step 2
    #     mtime_x64_1 = File.mtime("#{FAKE_BINARY_LOCATION}_x64")

    #     # Step 3
    #     FileUtils.rm(FAKE_BINARY_LOCATION)
    #     assert_equal(false, File.exist?(FAKE_BINARY_LOCATION), "Fake binary file should have been deleted")

    #     # Step 4
    #     sleep(2)
    #     d = create_driver
    #     d.run

    #     # Step 5
    #     assert_equal(false, File.exist?("#{FAKE_BINARY_LOCATION}_x64"), "#{FAKE_BINARY_LOCATION}_x64 should have been deleted")

    #     # Step 6
    #     assert_equal(true, File.exist?(FAKE_BINARY_LOCATION), "Fake binary file should have been created")

    #     # Step 7
    #     mtime_bin = File.mtime(FAKE_BINARY_LOCATION)
    #     assert(mtime_bin == mtime_x64_1, "The new binary should have a time of modification that is equal to x64 one")

    #     # Step 8
    #     FileUtils.cp(FAKE_BINARY_LOCATION, "#{FAKE_BINARY_LOCATION}_x64") if File.exist?(FAKE_BINARY_LOCATION)

    #     # Step 9
    #     mtime_bin_1 = File.mtime(FAKE_BINARY_LOCATION)

    #     # Step 10
    #     sleep(2)
    #     d.run

    #     # Step 11
    #     assert_equal(false, File.exist?("#{FAKE_BINARY_LOCATION}_x64"), "#{FAKE_BINARY_LOCATION}_x64 should have been deleted again")

    #     # Step 12
    #     assert_equal(true, File.exist?(FAKE_BINARY_LOCATION), "Fake binary file should have been created again")

    #     # Step 13
    #     mtime_bin_2 = File.mtime(FAKE_BINARY_LOCATION)
    #     assert(mtime_bin_2 > mtime_bin_1, "The new binary should have a modification that is newer or higher than earlier")

    # end
    
    # Test12: Check that "_x64" preceeds "_x32" if both staging are present
    # Sequence:
    # 1. Copy the binary file by appending "_x64" to name
    # 2. Copy the binary file by appending "_x32" to name
    # 3. Register run post condition as:
    #   (a) Wait for emit to have at least one error log
    # 4. Run the driver
    # 5. Assert that both 32, 64 found and picked 64 log is present
    # def test_case_12_check_x64_preceeds_x32
    #     # Step 1
    #     FileUtils.cp(FAKE_BINARY_LOCATION, "#{FAKE_BINARY_LOCATION}_x64") if File.exist?(FAKE_BINARY_LOCATION)

    #     # Step 2
    #     FileUtils.cp(FAKE_BINARY_LOCATION, "#{FAKE_BINARY_LOCATION}_x32") if File.exist?(FAKE_BINARY_LOCATION)

    #     # Step 3
    #     d = create_driver
    #     d.register_run_post_condition {
    #         sleep(100 * ONE_MSEC)
    #         true
    #     }

    #     # Step 4
    #     d.run
    #     error_logs = parse_diag_logs_from_emits(d.emits)

    #     # Step 5
    #     found_binary_duplicate_log = check_presence_of_error_log(error_logs, TEST_ERROR_LOG_BINARY_DUPLICATE)
    #     assert_equal(true, found_binary_duplicate_log, "Binary duplicate log in test should have been seen");
    # end

    # Test13: Check UID of binary connecting
    # Sequence:
    # 1. Check if current user is omsagent
    #   (a) If yes then declare success
    #   (b) else proceed further
    # 2. Set omsagentUID to current user uid
    # 3. Run the driver
    # 4. Check for error logs for invalid user error
    # 5. Assert absence of said error log
    # 6. Update omsagentUID to actual ones
    # 7. Run the driver
    # 8. Check for error logs for invalid user error
    # 9. Assert presence of said error log
    def test_case_13_binary_uid
        # Step 1
        omsagent_euid = -1
        begin
            omsagent_euid = Process::UID.from_name("omsagent")
        rescue ArgumentError => e
            return
        end
        return if Process.euid == omsagent_euid

        # Step 2
        d = create_driver
        d.instance.omsagentUID = Process.euid

        # Step 3
        d.register_run_post_condition {
            sleep (100 * ONE_MSEC)
        }
        d.run

        # Step 4
        error_logs = parse_diag_logs_from_emits(d.emits)
        found_invalid_user_log = check_presence_of_error_log_beginning_with(error_logs, TEST_ERROR_LOG_INVALID_USER)

        # Step 5
        assert_equal(false, found_invalid_user_log , "Invalid user log should not be seen");

        # Step 6
        d.instance.omsagentUID = Process::UID.from_name("omsagent")

        # Step 7
        d.register_run_post_condition {
            sleep (100 * ONE_MSEC)
        }
        d.run

        # Step 8
        error_logs = parse_diag_logs_from_emits(d.emits)
        found_invalid_user_log = check_presence_of_error_log_beginning_with(error_logs, TEST_ERROR_LOG_INVALID_USER)

        # Step 9
        assert_equal(true, found_invalid_user_log , "Invalid user log should have been seen");
    end

    # Test14: Check that omsagent is needed for cmd triggering
    # Sequence:
    # 1. Check if current user is omsagent
    #   (a) If yes then declare success
    #   (b) else proceed further
    # 2. Update UIDs as
    #   (a) omsagentUID as current user
    # 3. Register post condition as
    #   (a) Send error log via cmd
    # 4. Run the driver
    # 5. Assert that log is absent in emit
    # 6. Assert that invalid user log is present in emit
    # 7. Update UIDs as
    #   (a) omsagentUID as omsagent user
    # 8. Register post condition as
    #   (a) Send error log via cmd
    # 9. Run the driver
    #10. Assert that log is absent in emit
    #11. Assert that invalid user log is present in emit
    def test_case_14_omsagent_uid_for_cmd
        # Step 1
        omsagent_euid = -1
        begin
            omsagent_euid = Process::UID.from_name("omsagent")
        rescue ArgumentError => e
            return
        end
        return if Process.euid == omsagent_euid

        # Step 2
        d1 = create_driver
        d1.instance.omsagentUID = Process::UID.from_name("omsagent")

        # Step 3
        d1.register_run_post_condition {
            begin
                UNIXSocket.open(FAKE_UNIX_ENDPOINT) do |c|
                    c.puts "#{CMD_LOG_NPMD}:#{TEST_ERROR_LOG_EMIT}"
                end
                sleep (100 * ONE_MSEC)
            rescue => e
            end
        }

        # Step 4
        d1.run

        # Step 5
        error_logs = parse_diag_logs_from_emits(d1.emits)
        found_invalid_user_log = check_presence_of_error_log_beginning_with(error_logs, TEST_ERROR_LOG_INVALID_USER)
        found_error_emit_log = check_presence_of_error_log(error_logs, TEST_ERROR_LOG_EMIT)
        assert_equal(false, found_error_emit_log, "Error emit log should not seen when sent via non omsagent user")

        # Step 6
        assert_equal(true, found_invalid_user_log, "Invalid user log should be present when sent via non omsagent user")

        # Step 7
        d2 = create_driver
        d2.instance.omsagentUID = Process.euid

        # Step 8
        d2.register_run_post_condition {
            begin
                UNIXSocket.open(FAKE_UNIX_ENDPOINT) do |c|
                    c.puts "#{CMD_LOG_NPMD}:#{TEST_ERROR_LOG_EMIT}"
                end
                sleep (100 * ONE_MSEC)
            rescue => e
            end
        }

        # Step 9
        begin
            d2.run
        rescue IOError
            raise unless ["stream closed","closed stream"].include? $!.message
            died
        end

        # Step 10
        error_logs = parse_diag_logs_from_emits(d2.emits)
        found_invalid_user_log = check_presence_of_error_log_beginning_with(error_logs, TEST_ERROR_LOG_INVALID_USER)
        found_error_emit_log = check_presence_of_error_log(error_logs, TEST_ERROR_LOG_EMIT)
        assert_equal(true, found_error_emit_log, "Error emit log should be seen when sent via omsagent user")

        # Step 11
        assert_equal(false, found_invalid_user_log, "Invalid user log should not be present when sent via omsagent user")
    end

    # Test15: Delete binary but not version files and send log if setcap not supported
    # Sequence:
    # 1. Create npm_version file in local npm_state directory
    # 2. Update do_capability_check to true and set the verion file prefix
    # 3. Override the capabilties supported function to say false
    # 4. Register run post condition to basically wait for a while
    # 5. Run the driver
    # 6. Assert that fake binary file is absent
    # 7. Assert that npm_version file is present
    # 8. Assert that error log pertaining to absence of filesystem capabilities is emitted
    def test_case_15_no_cap_support_delete_binary_not_version_files
        # Step 1
        npmStateDir = "#{TMP_DIR}/#{Fluent::NPM::NPMD_STATE_DIR}"
        npmdVersionFile = "#{npmStateDir}/#{Fluent::NPM::NPMD_VERSION_FILE_NAME}"
        FileUtils.mkdir_p(npmStateDir)
        FileUtils.touch(npmdVersionFile)

        # Step 2
        d = create_driver
        d.instance.do_capability_check = true
        d.instance.npmd_state_dir = npmStateDir

        # Step 3
        d.instance.define_singleton_method(:is_filesystem_capabilities_supported) do
            false
        end

        # Step 4
        d.register_run_post_condition {
            sleep (100 * ONE_MSEC)
        }

        # Step 5
        d.run

        # Step 6
        assert_equal(false, File.exist?(FAKE_BINARY_LOCATION), "Error the fake binary should be absent as distro doesn't support capabilities")

        # Step 7
        assert_equal(true, File.exist?(npmdVersionFile), "Error the default npm_version file should be present")

        # Step 8
        error_logs = parse_diag_logs_from_emits(d.emits)
        found_cap_not_supported_log = check_presence_of_error_log(error_logs, TEST_ERROR_LOG_CAP_NOT_SUPPORTED)
        assert_equal(true, found_cap_not_supported_log, "Error should have seen filesystem capability not supported distro log")
    end

    # Test16: Delete version files and binary if capability is not to binary
    # Sequence:
    # 1. Create npm_version file in local npm_state directory
    # 2. Update do_capability_check to true and set the verion file prefix
    # 3. Override the capabilties supported function to say true
    # 4. Override the get capability string to mention no cap_net_raw found
    # 5. Run the driver
    # 6. Assert that fake binary file is absent
    # 7. Assert that npm_version file is absent
    def test_case_16_delete_binary_version_files_if_no_cap_set
        # Step 1
        npmStateDir = "#{TMP_DIR}/#{Fluent::NPM::NPMD_STATE_DIR}"
        npmdVersionFile = "#{npmStateDir}/#{Fluent::NPM::NPMD_VERSION_FILE_NAME}"
        FileUtils.mkdir_p(npmStateDir)
        FileUtils.touch(npmdVersionFile)

        # Step 2
        d = create_driver
        d.instance.do_capability_check = true
        d.instance.npmd_state_dir = npmStateDir

        # Step 3
        d.instance.define_singleton_method(:is_filesystem_capabilities_supported) do
            true
        end

        # Step 4
        d.instance.define_singleton_method(:get_capability_str) do |loc|
            ""
        end

        # Step 5
        d.run

        # Step 6
        assert_equal(false, File.exist?(FAKE_BINARY_LOCATION), "Error the fake binary should be absent as distro doesn't support capabilities")

        # Step 7
        assert_equal(false, File.exist?(npmdVersionFile), "Error the default npm_version file should be absent")
    end


    # Method test 02: Checking reading of workspace id from omsadmin conf path
    # The workspace id will be needed to single out instances running under a
    # particular computer id. Checking different cases for same
    def test_method_get_workspace_id
        d = create_driver
        test_ws_id = SecureRandom.uuid

        # Case 1: When omsadmin conf path is valid
        d.instance.omsadmin_conf_path = "/etc/opt/microsoft/omsagent/#{test_ws_id}/conf/omsadmin.conf"
        _result = d.instance.get_workspace_id()
        assert_equal(test_ws_id, _result, "The result should match with test_ws_id for valid case")

        # Case 2: Invalid number of path components
        d.instance.omsadmin_conf_path = "/etc/opt/microsoft/omsagent/conf/omsadmin.conf"
        _result = d.instance.get_workspace_id()
        assert_equal(nil, _result, "The result should be nil when path components are less")

        # Case 3: Ws Id is not of guid length
        d.instance.omsadmin_conf_path = "/etc/opt/microsoft/omsagent/#{test_ws_id}abcsd/conf/omsadmin.conf"
        _result = d.instance.get_workspace_id()
        assert_equal(nil, _result, "The result should be nil when ws id is not of guid length")
    end

    # Test02: Check if emit is working properly
    # Sequence:
    # 1. Register run post condition as:
    #   (a) Wait for emitted data has both path data and agent data
    # 2. Run the driver
    # 3. Assert that path data has Computer key
    # 4. Assert that there is no agent data
    def test_method_dontupload_agent_data_if_present_in_state
        # Step 1
        d = create_driver
        d.register_run_post_condition {
            (1..ONE_MIN_IN_MSEC).each do
                sleep(ONE_MSEC) unless (d.instance.num_path_data > 0 and d.instance.num_agent_data > 0)
            end

            assert(d.instance.num_path_data > 0, "Num path data should be greater than 0")
            assert(d.instance.num_agent_data > 0, "Num agent data should be greater than 0")
            true
        }

        # Step 2
        d.run
        emits = d.emits
        assert(emits.length > 0, "There should be at least 1 emitted item by now")
        path_data = nil
        agent_data = nil
        emits.each do |x|
            if x.last.key?("DataItems")
                x.last["DataItems"].each do |z|
                    if z.key?("SubType")
                        if z["SubType"] == "NetworkPath"
                            path_data ||= []
                            path_data << z
                        elsif z["SubType"] == "NetworkAgent"
                            agent_data ||= []
                            agent_data << z
                        end
                    end
                end
            end
        end

        # Step 3
        #assert(!path_data.nil?, "Path data should not be nil")
        #assert(path_data.length > 0, "There should be at least 1 path data element")
        #path_data.each do |x|
            #assert(x.key?("Computer"), "All path data elements should have Computer key appended")
        #end

        # Step 4
        #assert(!agent_data.nil?, "Agent data should not be nil")
        #assert(agent_data.length == 1, "There should be only 1 agent data element")
        #agent_data.each do |x|
            #assert(x.key?("AgentId"), "All agent data elements should have AgentId key appended")
        #end
    end

end
