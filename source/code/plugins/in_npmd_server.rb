# The npmd input plugin to fluentd
module Fluent
    class NPM < Input
        Fluent::Plugin.register_input('npmd', self)

        unless method_defined?(:router)
            define_method("router") {Fluent::Engine}
        end

        def initialize
            super
            require 'socket'
            require 'fileutils'
            require 'json'
            require 'securerandom'
            require 'etc'
            require 'enumerator'
            require 'pathname'

            require_relative 'npmd_config_lib'
            require_relative 'oms_common'
            @diagEnabled = false
            begin
                require_relative 'oms_diag_lib'
                @diagEnabled = OMS::Diag.IsDiagSupported()
            rescue LoadError
            end
        end

        CMD_START         = "StartNPM"
        CMD_STOP          = "StopNPM"
        CMD_CONFIG        = "Config"
        CMD_PURGE         = "Purge"
        CMD_LOG           = "ErrorLog"

        CONN_AGENT        = 1
        CONN_DSC          = 2
        CONN_UNKNOWN      = 3

        NPMD_CONN_CONFIRM = "NPMDAgent Connected!"

        NPM_DIAG          = "ErrorLog"

        STOP_SIGNAL       = "SIGKILL"

        CMD_ENUMERATE_PROCESSES_PREFIX = "ps aux | grep "

        MAX_LENGTH_DSC_COMMAND = 300
        MAX_ELEMENT_EMIT_CHUNK = 5000

        WATCHDOG_PET_INTERVAL_SECS    = 1 * 60 * 60 # 1 hour

        EXIT_RESTART_BACKOFF_TIMES_SECS = [60, 120, 300, 600, 1200, 2400]
        EXIT_RESTART_BACKOFF_THRES_SECS = 900

        NPMD_AGENT_CAPABILITY = "cap_net_raw+ep"
        NPMD_STATE_DIR = "/var/opt/microsoft/omsagent/npm_state"
        NPMD_VERSION_FILE_NAME = "npm_version"
        NPMD_LEGACY_VERSION_FILE = "/var/opt/microsoft/omsagent/state/npm_version"

        OMS_AGENTGUID_FILE = "/etc/opt/microsoft/omsagent/agentid"
        OMS_ADMIN_CONF_PATH_COMP_TOTAL = 8
        OMS_ADMIN_CONF_PATH_COMP_WS_IDX = 5
        GUID_LEN = 36
        START_TEXT = "\002"
        END_TEXT = "\003"

        DIAG_TAG = "diag.oms.npmd"
        DIAG_IPNAME = "NetworkMonitoring"
        DIAG_LOG_SRC_AGENT = "NpmdAgent"
        DIAG_LOG_SRC_PLUGIN = "InNPMPlugin"
        DIAG_LOG_SRC_DSC = "NpmDSC"
        DIAG_LOG_PROP_STD_ERR_TYPE = "StdErrorType"
        DIAG_LOG_STD_ERR = "Current"
        DIAG_LOG_PREV_STD_ERR = "Previous"
        DIAG_DEFAULT_PROPERTIES = {"Platform"=>"Linux"}

        config_param :omsadmin_conf_path,     :string, :default => "/etc/opt/microsoft/omsagent/conf/omsadmin.conf"
        config_param :location_unix_endpoint, :string, :default => "#{NPMD_STATE_DIR}/npmdagent.sock"
        config_param :location_control_data,  :string, :default => "/etc/opt/microsoft/omagent/conf/npmd_agent_config.xml"
        config_param :location_agent_binary,  :string, :default => "/opt/microsoft/omsagent/plugin/npmd_agent"
        config_param :tag, :string, :default => "oms.npmd"

        def configure(conf)
            super

            if !File.exist?(@omsadmin_conf_path)
                raise ConfigError, "no file #{@omsadmin_conf_path} exists"
            end
        end

        attr_accessor :agentId
        attr_accessor :binary_presence_test_string
        attr_accessor :binary_invocation_cmd
        attr_accessor :npmdClientSock
        attr_accessor :num_path_data, :num_agent_data
        attr_accessor :num_config_sent
        attr_accessor :is_purged
        attr_accessor :omsagentUID
        attr_accessor :do_capability_check
        attr_accessor :npmd_state_dir
        attr_accessor :dsc_resource_version

        def start
            # Fetch parameters related to instance
            @agentId = get_agent_id()
            return if @agentId.nil?
            @fqdn = get_fqdn()

            # Parameters that can be manipulated for testing
            @binary_presence_test_string = "npmd_agent" if @binary_presence_test_string.nil?
            @binary_invocation_cmd = @location_agent_binary if @binary_invocation_cmd.nil?
            @npmd_state_dir = NPMD_STATE_DIR if @npmd_state_dir.nil?
            @do_capability_check = true unless !@do_capability_check

            # Setup diagnostic based variables
            setup_diagnostic_params() if @dsc_resource_version.nil?

            # Setup steps for npmd_agent environment
            kill_all_agent_instances()
            upload_pending_stderrors()
            check_and_update_binaries()
            check_agent_capability() unless !@do_capability_check
            @is_shutdown = false
            setup_endpoint()
            @server_thread = Thread.new(&method(:server_run))
            @npmdIntendedStop = false
            @stderrFileNameHash = Hash.new
            @stop_sync = Mutex.new

            # Parameters for restart backoffs
            @agent_restart_count = 0
            @last_npmd_start = nil

            # Watchdog based recovery parameters
            @watch_dog_thread = nil
            @watch_dog_sync = Mutex.new
            @watch_dog_last_pet = Time.new

            # Start the npmd_agent
            start_npmd() if File.exist?(@location_agent_binary)
        end

        def shutdown
            Logger::logInfo "Received shutdown notification"
            @is_shutdown = true

            # Stop recovery
            Thread.kill(@watch_dog_thread) if @watch_dog_thread.is_a?(Thread)

            # Stopping the npmd_agent
            stop_npmd()

            # Set the npmd client socket as nil as npmd_reader might not do so in time
            @npmdClientSock.close() if !@npmdClientSock.nil?
            @npmdClientSock = nil

            # Stop server
            stop_server()

            # Kill stale agents if any
            kill_all_agent_instances()

            # Cleanup filesystem resources
            File.unlink(@location_unix_endpoint) if File.exist?@location_unix_endpoint
            if !@do_purge.nil? and @do_purge == true
                File.unlink(@location_agent_binary) if File.exist?@location_agent_binary
                delete_state_directory()
                @is_purged = true unless @is_purged.nil?
            end

            Logger::logInfo "Shutdown completed"
        end

        def setup_diagnostic_params
            @dsc_resource_version = "Unknown"
            _version_file_path = "#{@npmd_state_dir}/#{NPMD_VERSION_FILE_NAME}"
            if File.exist?_version_file_path
                _f = File.open(_version_file_path, 'r')
                _data = _f.read()
                @dsc_resource_version = _data.chomp if _data != ""
                _f.close()
            elsif File.exist?NPMD_LEGACY_VERSION_FILE
                _f = File.open(NPMD_LEGACY_VERSION_FILE, 'r')
                _data = _f.read()
                @dsc_resource_version = _data.chomp if _data != ""
                _f.close()
            end
        end

        def stop_server
            if @server_thread.is_a?(Thread)
                if File.exist?@location_unix_endpoint
                    begin
                        # Connect to the server to return from accept
                        UNIXSocket.open(@location_unix_endpoint) do |c|
                            c.puts ""
                            c.flush
                        end
                    rescue => e
                    end
                else
                    Thread.kill(@server_thread)
                end
            end
        end

        def setup_endpoint
            begin
                _dirname = File.dirname(@location_unix_endpoint)
                unless File.directory?(_dirname)
                    # This is setting up the npm_state directory
                    FileUtils.mkdir_p(_dirname)
                end
                if File.exists?(@location_unix_endpoint)
                    File.unlink(@location_unix_endpoint)
                end
                @server_obj = UNIXServer.new(@location_unix_endpoint)

                if File.exist?(@location_unix_endpoint)
                    FileUtils.chmod(0600, @location_unix_endpoint)
                end
            rescue StandardError => e
                log_error "Got error #{e}", Logger::resc
            end
        end

        def get_fqdn
            _fqdn = OMS::Common.get_fully_qualified_domain_name()
            _fqdn = OMS::Common.get_hostname() if _fqdn.nil?
            _fqdn
        end

        def check_and_get_json(text)
            begin
                _json = JSON.parse(text)
                _json
            rescue JSON::ParserError => e
                Logger::logInfo "Json parsing failed for #{text[0..200]} because of #{e}", Logger::resc
                nil
            end
        end

        def log_error(msg, depth=0)
            Logger::logError(msg, depth + 1)
            send_diag_log(msg, DIAG_LOG_SRC_PLUGIN)
        end

        def kill_all_agent_instances
            _cmd = "#{CMD_ENUMERATE_PROCESSES_PREFIX}".chomp + " " + @binary_presence_test_string.chomp
            _resultStr = `#{_cmd}`
            return if _resultStr.nil?
            _lines = _resultStr.split("\n")
            _lines.each do |line|
                if line.include?@binary_presence_test_string
                    _words = line.split()
                    _userName = _words[0]
                    _staleId = _words[1]
                    begin
                        _processOwnerId = Process::UID.from_name(_userName)
                        if (Process.uid == _processOwnerId)
                            Process.kill(STOP_SIGNAL, _staleId.to_i)
                        end
                    rescue Errno::ESRCH
                        # Process already stopped
                    rescue Errno::EPERM
                        # Trying to kill someone else's process?
                        log_error "No perm to kill process with info:#{line}: our uid:#{Process.uid}"
                    rescue ArgumentError
                        # Could not get info on username
                        log_error "Could not process username from info:#{line}: our uid:#{Process.uid}"
                    end
                end
            end
        end

        def npmd_reader
            begin
                begin
                    _line = @npmdClientSock.gets
                    if _line.nil? and !is_npmd_seen_in_ps()
                        @npmdClientSock = nil
                        Logger::logInfo "Exiting reader thread as npmdAgent found stopped"
                        break
                    end
                    @watch_dog_sync.synchronize do
                        @watch_dog_last_pet = Time.now
                    end
                    next if _line.nil? or _line.strip== ""
                    _json = check_and_get_json(_line.chomp)
                    unless !_json.nil?
                        Logger::logWarn "Sent string to plugin is not a json string", Logger::loop
                        log_error "String received not json: #{_line[0..100]}" if _line.bytesize > 50
                    else
                        unless _json.key?("DataItems") and !_json["DataItems"].nil? and _json["DataItems"] != ""
                            Logger::logWarn "No valid data items found in sent json #{_json}", Logger::loop
                        else
                            _uploadData = _json["DataItems"].reject {|x| x["SubType"] == NPM_DIAG}
                            _diagLogs   = _json["DataItems"].select {|x| x["SubType"] == NPM_DIAG}
                            _validUploadDataItems = Array.new
                            _subtypeList = ["EndpointHealth", "EndpointPath", "ExpressRoutePath", "EndpointDiagnostics", "ConnectionMonitorTestResult", "ConnectionMonitorPath", "NetworkAgentDiagnostics"]
                            _uploadData.each do |item|
                                if item.key?("SubType")
                                    # Append FQDN to path data
                                    if !@fqdn.nil? and item["SubType"] == "NetworkPath"
                                        @num_path_data += 1 unless @num_path_data.nil?
                                        _validUploadDataItems << item if is_valid_dataitem(item)
                                    # Append agent Guid to agent data
                                    elsif !@agentId.nil? and item["SubType"] == "NetworkAgent"
                                        @num_agent_data += 1 unless @num_agent_data.nil?
                                        _validUploadDataItems << item if is_valid_dataitem(item)
                                    # Append EPM, CM and ER data
                                    elsif _subtypeList.include?item["SubType"]
                                        Logger::logInfo "#{item["SubType"]} is uploaded"
                                        #Append UploadDirectly Flag to true for ConnectionMonitorPath as this flag will be used at NPM service
                                        if item["SubType"] == "ConnectionMonitorPath"
                                            item["UploadDirectly"] = "true"
                                        end
                                        _validUploadDataItems << item if is_valid_dataitem(item)
                                    else
                                        log_error "Invalid Subtype data received"
                                    end
                                end
                            end
                            emit_upload_data_dataitems(_validUploadDataItems) if !_validUploadDataItems.nil? and !_validUploadDataItems.empty?
                            emit_diag_log_dataitems_of_agent(_diagLogs) if !_diagLogs.nil? and !_diagLogs.empty?
                        end
                    end
                rescue StandardError => e
                    unless is_npmd_seen_in_ps()
                        @npmdClientSock = nil
                        Logger::logInfo "Exiting reader thread. NPMD found stopped", Logger::loop + Logger::resc
                        break;
                    else
                        log_error "Got error while reading data from NPMD: #{e}", Logger::loop + Logger::resc
                    end
                end
            end while !@npmdClientSock.nil?
        end

        def is_valid_dataitem(item)
            _itemType=""
            if item["SubType"] == "NetworkAgent"
                _itemType = NPMContract::DATAITEM_AGENT
            elsif item["SubType"] == "NetworkPath"
                _itemType = NPMContract::DATAITEM_PATH
            elsif item["SubType"] == NPM_DIAG
                _itemType = NPMContract::DATAITEM_DIAG
            elsif item["SubType"] == "EndpointHealth"
                _itemType = NPMContract::DATAITEM_ENDPOINT_HEALTH
            elsif item["SubType"] == "EndpointPath"
                _itemType = NPMContract::DATAITEM_ENDPOINT_MONITORING
            elsif item["SubType"] == "EndpointDiagnostics"
                _itemType = NPMContract::DATAITEM_ENDPOINT_DIAGNOSTICS
            elsif item["SubType"] == "ExpressRoutePath"
                _itemType = NPMContract::DATAITEM_EXROUTE_MONITORING
            elsif item["SubType"] == "ConnectionMonitorTestResult"
                _itemType = NPMContract::DATAITEM_CONNECTIONMONITOR_TEST
            elsif item["SubType"] == "ConnectionMonitorPath"
                _itemType = NPMContract::DATAITEM_CONNECTIONMONITOR_PATH
            elsif item["SubType"] == "NetworkAgentDiagnostics"
                _itemType = NPMContract::DATAITEM_AGENT_DIAGNOSTICS
            end

            return false if _itemType.empty?

            _res, _prob = NPMContract::IsValidDataitem(item, _itemType)

            return true if _res == NPMContract::DATAITEM_VALID
            if (_res == NPMContract::DATAITEM_ERR_INVALID_FIELDS)
                Logger::logInfo "Invalid key in #{item["SubType"]} data: #{_prob}"
            elsif (_res == NPMContract::DATAITEM_ERR_MISSING_FIELDS)
                Logger::logInfo "Key #{_prob} absent in #{item["SubType"]} data"
            elsif (_res == NPMContract::DATAITEM_ERR_INVALID_TYPE)
                Logger::logInfo "Invalid itemtype #{_itemType}"
            end
        end

        def send_diag_log(msg, logSource, properties = Hash.new)
            # Send to diagnostic channel if supported
            if @diagEnabled
                properties.merge!(DIAG_DEFAULT_PROPERTIES)
                properties['Component'] = logSource
                properties['Version'] = @dsc_resource_version
                properties['LogTag'] = "NPMDiagLnx"
                OMS::Diag.LogDiag(msg, DIAG_TAG, DIAG_IPNAME, properties)
            else
                _dataitem = Hash.new
                _dataitem["Component"] = logSource
                _dataitem["Version"] = @dsc_resource_version
                _dataitem["Message"] = msg
                _dataitem["LogTag"] = "NPMDiagLnx"
                _record = Hash.new
                _record["DataType"] = "HEALTH_ASSESSMENT_BLOB"
                _record["IPName"] = "LogManagement"
                _record["DataItems"] = _dataitem
                router.emit(@tag, Engine.now, _record)
            end
        end

        def emit_diag_log_dataitems_of_agent(dataitems)
            dataitems.each  do |d|
                send_diag_log(d["Message"], DIAG_LOG_SRC_AGENT) if is_valid_dataitem(d)
            end
        end

        def emit_upload_data_dataitems(dataitems)
            dataitems.each_slice(MAX_ELEMENT_EMIT_CHUNK) do |items|
                _record = Hash.new
                _record["DataType"] = "NETWORK_MONITORING_BLOB"
                _record["IPName"]   = "NetworkMonitoring"
                _record["DataItems"] = items
                router.emit(@tag, Engine.now, _record)
            end
        end

        def check_and_update_binaries
            _x32BinPath = "#{@location_agent_binary}_x32"
            _x64BinPath = "#{@location_agent_binary}_x64"
            _x32Present = File.exist?(_x32BinPath)
            _x64Present = File.exist?(_x64BinPath)
            _binPresent = File.exist?(@location_agent_binary)

            if !_binPresent and !_x32Present and !_x64Present
                log_error "Binary not found at given location"
            elsif _x32Present or _x64Present
                if _x32Present and _x64Present
                    log_error "Found both x64 and x32 staging binaries"
                end

                File.unlink(@location_agent_binary) if _binPresent

                if _x64Present
                    FileUtils.mv(_x64BinPath, @location_agent_binary)
                else
                    FileUtils.mv(_x32BinPath, @location_agent_binary)
                end
            end

            File.unlink(_x32BinPath) if File.exist?(_x32BinPath)
            File.unlink(_x64BinPath) if File.exist?(_x64BinPath)
        end

        def is_filesystem_capabilities_supported
            _isGetCap = `whereis getcap`
            _isGetCap.chomp!
            if _isGetCap == "getcap:"
                false
            else
                true
            end
        end

        def get_capability_str(loc)
            _getCapResult = `getcap #{@location_agent_binary}`
        end

        def check_agent_capability
            _deleteStateDir = false
            _deleteBinary = false
            _isCapSupported = is_filesystem_capabilities_supported()

            if !_isCapSupported
                _deleteBinary = true
                log_error "Distro has no support for filesystem capabilities"
            elsif !File.exist?(@location_agent_binary)
                _deleteStateDir = true
            else
                _getCapResult = get_capability_str(@location_agent_binary)
                if !_getCapResult.include?(NPMD_AGENT_CAPABILITY)
                    _deleteBinary = true
                    _deleteStateDir = true
                end
            end

            # Delete state directory to allow DSC to copy binaries and setup
            delete_state_directory() if _deleteStateDir

            # We delete the binary because we do not want ruby to start it
            if _deleteBinary and File.exist?(@location_agent_binary)
                File.unlink(@location_agent_binary)
            end

        end

        def get_workspace_id()
            if !@omsadmin_conf_path.nil?
                path = nil
                begin
                    path = Pathname.new(@omsadmin_conf_path).cleanpath
                rescue
                    return nil
                end
                _arr = "#{path}".split('/')
                if (_arr.length == OMS_ADMIN_CONF_PATH_COMP_TOTAL and _arr[OMS_ADMIN_CONF_PATH_COMP_WS_IDX].length == GUID_LEN)
                    return _arr[OMS_ADMIN_CONF_PATH_COMP_WS_IDX]
                end
            end
            nil
        end

        def get_agent_id
            agentid_lines = IO.readlines(@omsadmin_conf_path).select { |line| line.start_with?("AGENT_GUID=")}
            if agentid_lines.size == 0
                return nil
            else
                return agentid_lines[0].split("=")[1].strip
            end
        end

        def process_dsc_command(cmd)
            return if cmd.nil?
            _req = cmd.chomp

            if _req.start_with?CMD_START
                Logger::logInfo "Processing NPMD Start command"
                start_npmd()
            elsif _req.start_with?CMD_STOP
                Logger::logInfo "Processing NPMD Stop command"
                stop_npmd()
            elsif _req.start_with?CMD_CONFIG
                Logger::logInfo "Processing new configuration for NPMD"
                send_config()
            elsif _req.start_with?CMD_PURGE
                Logger::logInfo "Processing NPMD Purge"
                @do_purge = true
                shutdown()
            elsif _req.start_with?CMD_LOG
                Logger::logInfo "Processing error log"
                _ind = _req.index(":")
                _msg = _req[_ind+1..-1]
                unless _ind.nil? or _ind + 1 >= _req.length
                    Logger::logInfo "dsc:#{_msg}"
                    send_diag_log(_msg, DIAG_LOG_SRC_DSC)
                end
            else
                log_error "Unknown command #{cmd} received from DSC resource provider"
            end
        end

        def is_npmd_seen_in_ps
            return false if @npmdProcessId.nil?
            begin
                Process.getpgid(@npmdProcessId.to_i)
                true
            rescue Errno::ESRCH
                false
            end
        end

        def delete_state_directory
            if File.directory?(@npmd_state_dir)
                FileUtils.rm_rf(@npmd_state_dir)
            end
        end

        def upload_pending_stderrors
            _logProperties = Hash.new
            _logProperties[DIAG_LOG_PROP_STD_ERR_TYPE] = DIAG_LOG_PREV_STD_ERR
            begin
                _globPrefix = "#{@npmd_state_dir}/stderror_"
                _fileList = Dir["#{_globPrefix}*"]
                _fileList.each do |x|
                    _msg = ""
                    File.readlines(x).each do |line|
                        Logger::logInfo "Prev STDERR: #{line}", 2*Logger::loop
                        _msg += "#{line} "
                    end
                    File.unlink(x)
                    # Sending one diag log per file
                    send_diag_log(_msg, DIAG_LOG_SRC_PLUGIN, _logProperties)
                end
            rescue => e
                Logger::logInfo "Got error while uploading pending stderrors: #{e}"
            end
        end

        def handle_exit(_processId)
            _exitRes = Process.waitpid2(_processId)
            _logProperties = Hash.new
            _logProperties[DIAG_LOG_PROP_STD_ERR_TYPE] = DIAG_LOG_STD_ERR

            @stop_sync.synchronize do
                @stderrFileNameHash.each do |procId, fileName|
                    begin
                        if File.exist?(fileName)
                            _msg = ""
                            File.readlines(fileName).each do |line|
                                Logger::logInfo "STDERR for PID:#{procId}:#{line}"
                                _msg += "#{line} "
                            end
                            _logProperties["PID"] = procId
                            send_diag_log(_msg, DIAG_LOG_SRC_PLUGIN, _logProperties)
                            File.unlink(fileName)
                            @npmdProcessId = nil if @npmdProcessId == procId
                        end
                    rescue => e
                        log_error "Got error while processing stderr files: #{e}"
                    end
                end
                @stderrFileNameHash.clear()
            end

            # Checking if NPMD exited as planned
            if @npmdIntendedStop
                Logger::logInfo "NpmdAgent exited normally"
            else
                # only place for restarting crashed NPMD
                log_error "NpmdAgent ended with exit status #{_exitRes[1]}"

                _currentTime = Time.now
                @stop_sync.synchronize do
                    if !@last_npmd_start.nil? and
                       (_currentTime - @last_npmd_start) < EXIT_RESTART_BACKOFF_THRES_SECS
                        if @agent_restart_count >= EXIT_RESTART_BACKOFF_TIMES_SECS.length
                            @agent_restart_count = EXIT_RESTART_BACKOFF_TIMES_SECS.length
                        else
                            @agent_restart_count += 1
                        end
                        _sleepFor = EXIT_RESTART_BACKOFF_TIMES_SECS[@agent_restart_count - 1]
                        Logger::logInfo "Sleeping for #{_sleepFor} secs before restarting agent"
                        sleep(_sleepFor)
                    else
                        @agent_restart_count = 0
                    end
                end

                Logger::logInfo "Restarting NPMD"
                start_npmd()
            end
        end

        def start_npmd
            @stop_sync.synchronize do
                unless is_npmd_seen_in_ps()
                    @npmdIntendedStop = false
                    _stderrFileName = "#{File.dirname(@location_unix_endpoint)}/stderror_#{SecureRandom.uuid}.log"
                    begin
                        @npmdProcessId = Process.spawn(@binary_invocation_cmd, :err=>_stderrFileName)
                        @last_npmd_start = Time.now
                        @stderrFileNameHash[@npmdProcessId] = _stderrFileName
                        _t = Thread.new {handle_exit(@npmdProcessId)}
                        Logger::logInfo "NPMD Agent running with process id #{@npmdProcessId}"
                    rescue
                        log_error "Unable to spawn NPMD Agent binary"
                    end
                else
                    Logger::logInfo "Npmd already seen in PS"
                end
            end
        end

        def stop_npmd
            if defined?@npmdProcessId and is_npmd_seen_in_ps()
                @stop_sync.synchronize do
                    @npmdIntendedStop = true
                    Process.kill(STOP_SIGNAL, @npmdProcessId.to_i)
                end
            else
                Logger::logInfo "NPMD agent found already stopped"
            end
        end

        def send_config
            begin # checking for File call errors with this config file
                unless File.exist?(@location_control_data)
                    Logger::logWarn "No file #{@location_control_data} found at location"
                else
                    if defined?@npmdClientSock and !@npmdClientSock.nil?

                        # Read the UI configuration from file location
                        _uiXml = File.read(@location_control_data)
                        if _uiXml.nil? or _uiXml == ""
                            Logger::logWarn "File read at #{@location_control_data} got nil or empty string"
                            return
                        end

                        # Transform the UI XML configuration to agent configuration
                        _agentConfig, _errorSummary = NPMDConfig::GetAgentConfigFromUIConfig(_uiXml)
                        if _agentConfig.nil? or _agentConfig == ""
                            Logger::logWarn "Agent configuration transformation returned empty"
                            return
                        end

                        if _errorSummary.strip != ""
                            log_error "Configuration drops: #{_errorSummary}"
                        end

                        @npmdClientSock.puts START_TEXT + _agentConfig + END_TEXT
                        @npmdClientSock.flush
                        @num_config_sent += 1 unless @num_config_sent.nil?
                        Logger::logInfo "Configuration file sent to npmd_agent"

                        # Start the watch dog thread after first config
                        @watch_dog_thread = Thread.new(&method(:watch_dog_wait_for_pet)) if @watch_dog_thread.nil?

                    else
                        Logger::logWarn "NPMD client socket not connected yet!"
                    end
                end
            rescue RuntimeError => e
                log_error "Error while sending config: #{e}", Logger::resc
            end
        end

        def triage_conn(clientSock)
            begin
                @omsagentUID = Process::UID.from_name("omsagent") if @omsagentUID.nil?
                _opt = clientSock.getsockopt(Socket::Constants::SOL_SOCKET,
                                             Socket::Constants::SO_PEERCRED)
                _pid, _euid, _egid = _opt.unpack("i3")

                if _euid == @omsagentUID
                    # Check if this is NPMDAgent binary
                    if !@npmdProcessId.nil? and _pid == @npmdProcessId.to_i
                        _rawLine = clientSock.gets
                        return CONN_AGENT if (!_rawLine.nil? and _rawLine.chomp == NPMD_CONN_CONFIRM)
                    else
                        # This is DSC command
                        return CONN_DSC
                    end
                else
                    # Invalid user id
                    _psswd = Etc.getpwuid(_euid)
                    _uname = _psswd.name
                    _fullname = _psswd.gecos
                    log_error "Invalid user:#{_uname}:<#{_fullname}> communicated with NPM plugin"
                end
            rescue => e
                log_error "error: #{e}"
            end
            CONN_UNKNOWN
        end

        def server_run
            unless defined?@server_obj and !@server_obj.nil?
                Logger::logInfo "Server obj was not created properly, Exiting"
            else
                Logger::logInfo "Got FQDN as #{@fqdn} and AgentID as #{@agentId}"
                loop do
                    _client = @server_obj.accept
                    return if @is_shutdown == true
                    _clientTriage = triage_conn(_client)
                    if _clientTriage == CONN_AGENT
                        Logger::logInfo "NPMD Agent connected"
                        @npmdClientSock.close() unless @npmdClientSock.nil?
                        Thread.kill(@npmdAgentReaderThread) if @npmdAgentReaderThread.is_a?(Thread)
                        @npmdClientSock = _client
                        @npmdAgentReaderThread = Thread.new{npmd_reader()}
                        send_config()
                    elsif _clientTriage == CONN_DSC
                        _rawLine, _senderInfo = _client.recvfrom(MAX_LENGTH_DSC_COMMAND)
                        process_dsc_command(_rawLine) if !_rawLine.nil?
                    end
                end
            end
        end

        def watch_dog_wait_for_pet
            _sleepInterval = WATCHDOG_PET_INTERVAL_SECS

            # Pet right after first agent configuration is sent
            @watch_dog_sync.synchronize do
                @watch_dog_last_pet = Time.now
            end

            loop do
                sleep(_sleepInterval)
                _diffTime = Time.now

                @watch_dog_sync.synchronize do
                    _diffTime -= @watch_dog_last_pet
                end

                if _diffTime > WATCHDOG_PET_INTERVAL_SECS
                    # Case when watchdog would bark
                    watch_dog_bark()
                    _sleepInterval = WATCHDOG_PET_INTERVAL_SECS
                else
                    # Sleep for interval period from last update time
                    _sleepInterval = WATCHDOG_PET_INTERVAL_SECS - _diffTime
                end
                _sleepInterval = WATCHDOG_PET_INTERVAL_SECS if _sleepInterval > WATCHDOG_PET_INTERVAL_SECS
            end
        end

        def watch_dog_bark
            if defined?@npmdProcessId and is_npmd_seen_in_ps()
                log_error "WatchDog: Killing agent for restart"
                Process.kill(STOP_SIGNAL, @npmdProcessId.to_i)
            else
                log_error "WatchDog: NPMD agent found already stopped"
            end
        end

    end
end
