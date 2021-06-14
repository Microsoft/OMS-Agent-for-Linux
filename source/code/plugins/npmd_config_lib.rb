class Logger

    require 'thread'

    LOG_DEPTH_INC_RESC = 1 # Depth increase of method scope for rescue
    LOG_DEPTH_INC_LOOP = 2 # Depth increase of method scope for loop

    def self.log_error(msg, depth=0)
        _methodname = getMethodname(depth)
        _message = "[#{_methodname}]:#{msg}"
        $log.error "[NPMD]:#{_message}"
    end
    def self.log_info(msg, depth=0)
        _methodname = getMethodname(depth)
        $log.info "[NPMD]:[#{_methodname}]:#{msg}"
    end
    def self.log_warn(msg, depth=0)
        _methodname = getMethodname(depth)
        $log.warn "[NPMD]:[#{_methodname}]:#{msg}"
    end

    class << self
        alias_method :logError, :log_error
        alias_method :logInfo,  :log_info
        alias_method :logWarn,  :log_warn
    end

    private

    def self.getMethodname(depth)
        _depth = depth > 0 ? depth : 0
        begin
            caller_locations(2 + _depth, 1)[0].label
        rescue
            caller_locations(2 + LOG_DEPTH_INC_RESC, 1)[0].label
        end
    end

    def self.loop
        LOG_DEPTH_INC_LOOP
    end

    def self.resc
        LOG_DEPTH_INC_RESC
    end
end

# Module to parse config received from DSC and generate Agent Configuration
module NPMDConfig

    require 'rexml/document'
    require 'json'
    require 'ipaddr'
    require 'socket'

    # Need to have method to get the subnetmask
    class ::IPAddr
        def getNetMaskString
            _to_string(@mask_addr)
        end
    end

    # This class holds the methods for creating
    # a config understood by NPMD Agent from a hash
    class AgentConfigCreator
        public

        # Variables for tracking errors
        @@agent_ip_drops = 0
        @@agent_drops = 0
        @@network_subnet_drops = 0
        @@network_drops = 0
        @@rule_subnetpair_drops = 0
        @@rule_drops = 0

        # Strings utilized in drop summary
        DROP_IPS        = "Agent IPs"
        DROP_AGENTS     = "Agents"
        DROP_SUBNETS    = "Network subnets"
        DROP_NETWORKS   = "Networks"
        DROP_SUBNETPAIRS= "Rule subnetpairs"
        DROP_RULES      = "Rules"

        # Reset error checking
        def self.resetErrorCheck
            @@agent_ip_drops = 0
            @@agent_drops = 0
            @@network_subnet_drops = 0
            @@network_drops = 0
            @@rule_subnetpair_drops = 0
            @@rule_drops = 0
        end

        # Generating the error string
        def self.getErrorSummary
            _agentIpDrops=""
            _agentDrops=""
            _networkSNDrops=""
            _networkDrops=""
            _ruleSNPairDrops=""
            _ruleDrops=""

            if @@agent_ip_drops != 0
                _agentIpDrops = "#{DROP_IPS}=#{@@agent_ip_drops}"
            end
            if @@agent_drops != 0
                _agentDrops= "#{DROP_AGENTS}=#{@@agent_drops}"
            end
            if @@network_subnet_drops != 0
                _networkSNDrops = "#{DROP_SUBNETS}=#{@@network_subnet_drops}"
            end
            if @@network_drops != 0
                _networkDrops = "#{DROP_NETWORKS}=#{@@network_drops}"
            end
            if @@rule_subnetpair_drops != 0
                _ruleSNPairDrops = "#{DROP_SUBNETPAIRS}=#{@@rule_subnetpair_drops}"
            end
            if @@rule_drops != 0
                _ruleDrops = "#{DROP_RULES}=#{@@rule_drops}"
            end
            _str =  _agentIpDrops + " " + _agentDrops + " " +
                    _networkSNDrops + " " + _networkDrops + " " +
                    _ruleSNPairDrops + " " + _ruleDrops
        end

        # Only accessible method
        def self.createJsonFromUIConfigHash(configHash)
            begin
                if configHash == nil
                    Logger::logError "Config received is NIL"
                    return nil
                end
                _subnetInfo = getProcessedSubnetHash(configHash["Subnets"])
                _doc = {"Configuration" => {}}
                _doc["Configuration"] ["Metadata"] = createMetadataElements(configHash["Metadata"])
                _doc["Configuration"] ["Agents"] = createAgentElements(configHash["Agents"], _subnetInfo["Masks"])
                _doc["Configuration"] ["Networks"] = createNetworkElements(configHash["Networks"], _subnetInfo["IDs"])
                _doc["Configuration"] ["Rules"] = createRuleElements(configHash["Rules"], _subnetInfo["IDs"]) unless !configHash.has_key?("Rules")
                _doc["Configuration"] ["Epm"] = createEpmElements(configHash["Epm"]) unless !configHash.has_key?("Epm")
                _doc["Configuration"] ["ER"] = createERElements(configHash["ER"]) unless !configHash.has_key?("ER")

                _configJson = _doc.to_json
                _configJson
            rescue StandardError => e
                Logger::logError "Got error creating JSON from UI Hash: #{e}", Logger::resc
                raise "Got error creating AgentJson: #{e}"
            end
        end

        private

        def self.getNetMask(ipaddrObj)
            _tempIp = IPAddr.new(ipaddrObj.getNetMaskString)
            _tempIp.to_s
        end

        def self.getProcessedSubnetHash(subnetHash)
            _h = Hash.new
            _h["Masks"] = Hash.new
            _h["IDs"] = Hash.new
            begin
                subnetHash.each do |key, value|
                    _tempIp = IPAddr.new(value)
                    _h["Masks"][key] = getNetMask(_tempIp)
                    _h["IDs"][key] = value
                end
                _h
            rescue StandardError => e
                Logger::logError "Got error while creating subnet hash: #{e}", Logger::resc
                nil
            end
        end

        def self.createMetadataElements(metadataHash)
            _metadata = Hash.new
            _metadata["Version"] = metadataHash.has_key?("Version") ? metadataHash["Version"] : String.new
            _metadata["Protocol"] = metadataHash.has_key?("Protocol") ? metadataHash["Protocol"] : String.new
            _metadata["SubnetUid"] = metadataHash.has_key?("SubnetUid") ? metadataHash["SubnetUid"] : String.new
            _metadata["AgentUid"] = metadataHash.has_key?("AgentUid") ? metadataHash["AgentUid"] : String.new
            _metadata[:"WorkspaceResourceId"] = metadataHash["WorkspaceResourceID"] if metadataHash.has_key?("WorkspaceResourceID")
            _metadata[:"WorkspaceId"] = metadataHash["WorkspaceID"] if metadataHash.has_key?("WorkspaceID")
            _metadata[:"LastUpdated"] = metadataHash["LastUpdated"] if metadataHash.has_key?("LastUpdated")
            return _metadata
        end

        def self.createAgentElements(agentArray, maskHash)
            _agents = Array.new
            agentArray.each do |x|
                _agent = Hash.new
                _agent["Name"] = x["Guid"];
                _agent["Capabilities"] = x["Capability"].to_s;
                _agent["ResourceId"] = x["ResourceId"].to_s;
                _agent["IPConfiguration"] = [];
                
                x["IPs"].each do |ip|
                    _ipConfig = Hash.new
                    _ipConfig["IP"] = ip["IP"];
                    _subnetMask = maskHash[ip["SubnetName"]];
                    if _subnetMask.nil?
                        Logger::logWarn "Did not find subnet mask for subnet name #{ip["SubnetName"]} in hash", 2*Logger::loop
                        @@agent_ip_drops += 1
                    else
                        _ipConfig["Mask"] = maskHash[ip["SubnetName"]];
                    end
                    _agent["IPConfiguration"].push(_ipConfig);
                end
                _agents.push(_agent);
                if _agents.empty?
                    @@agent_drops += 1
                end
            end
            _agents
        end

        def self.createNetworkElements(networkArray, subnetIdHash)
            _networks = Array.new
            networkArray.each do |x|
                _network = Hash.new
                _network["Name"] = x["Name"];
                _network["Subnet"] = Array.new
                x["Subnets"].each do |sn|
                    _subnet = Hash.new
                    _subnetId = subnetIdHash[sn]
                    if _subnetId.nil?
                        Logger::logWarn "Did not find subnet id for subnet name #{sn} in hash", 2*Logger::loop
                        @@network_subnet_drops += 1
                    else
                        _subnet["ID"] = subnetIdHash[sn];
                        _subnet["Disabled"]  = "False" # TODO
                        _subnet["Tag"]  = "" # TODO
                    end
                    _network["Subnet"].push(_subnet);
                end
                _networks.push(_network);
                if _networks.empty?
                    @@network_drops += 1                    
                end
            end
            _networks
        end

        def self.createActOnElements(elemArray, subnetIdHash)
            _networkTestMatrix = Array.new
            elemArray.each do |a|
                _sSubnetId = "*"
                _dSubnetId = "*"
                if a["SS"] != "*" and a["SS"] != ""
                    _sSubnetId = subnetIdHash[a["SS"].to_s]
                end
                if a["DS"] != "*" and a["DS"] != ""
                    _dSubnetId = subnetIdHash[a["DS"].to_s]
                end
                if _sSubnetId.nil?
                    Logger::logWarn "Did not find subnet id for source subnet name #{a["SS"].to_s} in hash", 2*Logger::loop
                    @@rule_subnetpair_drops += 1
                elsif _dSubnetId.nil?
                    Logger::logWarn "Did not find subnet id for destination subnet name #{a["DS"].to_s} in hash", 2*Logger::loop
                    @@rule_subnetpair_drops += 1
                else
                    # Process each subnetpair
                    _snPair = Hash.new
                    _snPair["SourceSubnet"] = _sSubnetId
                    _snPair["SourceNetwork"] = a["SN"]
                    _snPair["DestSubnet"] = _dSubnetId
                    _snPair["DestNetwork"] = a["DN"]
                    _networkTestMatrix.push(_snPair);
                end
            end
            _networkTestMatrix
        end

        def self.createRuleElements(ruleArray, subnetIdHash)
            _rules = Array.new
            ruleArray.each do |x|
                _rule = Hash.new
                _rule["Name"] = x["Name"];
                _rule["Description"] = x["Description"]
                _rule["Protocol"] = x["Protocol"].to_s;
                _rule["NetworkTestMatrix"] = createActOnElements(x["Rules"], subnetIdHash);
                _rule["AlertConfiguration"] = Hash.new;
                _rule["Exceptions"] = createActOnElements(x["Exceptions"], subnetIdHash);
                _rule["DiscoverPaths"] = x["DiscoverPaths"].to_s
                _rule["Port"] = x["Port"].to_s
                _rule["ListenOnPort"] = x["ListenOnPort"]
                _rule["BiDirectional"] = x["BiDirectional"]
                _rule["TestFrequencyInSec"] = x["Frequency"]
                _rule["CMResourceId"] = x.has_key?("CMResourceId") ? x["CMResourceId"] : String.new
                _rule["IngestionWorkspaceId"] = x.has_key?("IngestionWorkspaceId") ? x["IngestionWorkspaceId"] : String.new
                _rule["WorkspaceAlias"] = x.has_key?("WorkspaceAlias") ? x["WorkspaceAlias"] : String.new
                _rule["WorkspaceResourceId"] = x["WorkspaceResourceId"]

                if _rule["NetworkTestMatrix"].empty?
                    Logger::logWarn "Skipping rule #{x["Name"]} as network test matrix is empty", Logger::loop
                    @@rule_drops += 1
                else
                    # Alert Configuration
                    _rule["AlertConfiguration"]["ChecksFailedPercent"]  = x["LossThreshold"].to_s
                    _rule["AlertConfiguration"]["RoundTripTimeMs"]  = x["LatencyThreshold"].to_s
                end
                if !_rule.empty?
                    _rules.push(_rule)
                end
            end
            _rules
        end

        def self.createEpmElements(epmHash)
            return if epmHash.nil?
            _epmRules = Hash.new
            _rule = Array.new
            epmHash.each do |key, rules|
                for i in 0..rules.length-1
                    _ruleHash = Hash.new
                    _iRule = rules[i] # get individual rule
                    _ruleHash["ID"] = _iRule["ID"]
                    _ruleHash["Name"] = _iRule["Name"]
                    _ruleHash["CMResourceId"] = _iRule.has_key?("CMResourceId") ? _iRule["CMResourceId"] : String.new
                    _ruleHash["IngestionWorkspaceId"] = _iRule.has_key?("IngestionWorkspaceId") ? _iRule["IngestionWorkspaceId"] : String.new
                    _ruleHash["WorkspaceAlias"] = _iRule.has_key?("WorkspaceAlias") ? _iRule["WorkspaceAlias"] : String.new
                    _ruleHash["Redirect"] = "false"
                    _ruleHash["WorkspaceResourceId"] = _iRule["WorkspaceResourceId"]
                    _ruleHash["DiscoverPaths"] = _iRule.has_key?("DiscoverPaths") ? _iRule["DiscoverPaths"].to_s : "true"
                    _ruleHash["NetTests"] = (_iRule["NetworkThresholdLoss"].to_i >= -2 and _iRule["NetworkThresholdLatency"].to_i >= -2) ? "true" : "false"
                    _ruleHash["AppTests"] = (_iRule["AppThresholdLatency"].to_i >= -2) ? "true" : "false"
                    _ruleHash["ValidStatusCodeRanges"] = _iRule.has_key?("ValidStatusCodeRanges") ? _iRule["ValidStatusCodeRanges"] : nil;
                    _ruleHash["SourceAgentIds"] = _iRule["SourceAgentIds"]

                    if (_ruleHash["NetTests"] == "true")
                        _ruleHash["NetworkThreshold"] = {"ChecksFailedPercent" => _iRule["NetworkThresholdLoss"].to_s, "RoundTripTimeMs" => _iRule["NetworkThresholdLatency"].to_s}
                    end

                    if (_ruleHash["AppTests"] == "true")
                        _ruleHash["AppThreshold"] = {"ChecksFailedPercent" => (_iRule.has_key?("AppThresholdLoss") ? _iRule["AppThresholdLoss"].to_s : nil), "RoundTripTimeMs" => _iRule["AppThresholdLatency"].to_s}
                    end

                    # Fill endpoints
                    _epList = _iRule["Endpoints"]
                    _endpointList = Array.new
                    for j in 0.._epList.length-1
                        _epHash = Hash.new
                        _epHash["Name"] = _epList[j]["Name"]
                        _epHash["ID"] = _epList[j]["Id"]
                        _epHash["DestAddress"] = _epList[j]["URL"]
                        _epHash["DestPort"] = _epList[j]["Port"].to_s
                        _epHash["TestProtocol"] = _epList[j]["Protocol"]
                        _epHash["MonitoringInterval"] = _iRule["Poll"].to_s
                        _epHash["TimeDrift"] = _epList[j]["TimeDrift"].to_s
                        _epHash["Type"] = _epList[j]["Type"].to_s
                        _epHash["ListenOnPort"] = _epList[j]["ListenOnPort"]
                        _endpointList.push(_epHash)
                    end
                    _ruleHash["Endpoints"] = _endpointList
                    _rule.push(_ruleHash)
                end
            end
            _epmRules["Rules"] = _rule
            _epmRules
        end

        def self.createERElements(erHash)
            return if erHash.nil?
            _er = Hash.new
            erHash.each do |key, rules|
                # Fill Private Peering Rules
                if key == "PrivatePeeringRules"
                    _ruleList = Array.new
                    for i in 0..rules.length-1
                        _pvtRule = Hash.new
                        _iRule = rules[i]
                        _pvtRule["Name"] = _iRule["Name"]
                        _pvtRule["ConnectionResourceId"] = _iRule["ConnectionResourceId"]
                        _pvtRule["CircuitResourceId"] = _iRule["CircuitResourceId"]
                        _pvtRule["CircuitName"] = _iRule["CircuitName"]
                        _pvtRule["VirtualNetworkName"] = _iRule["vNetName"]
                        _pvtRule["Protocol"] = _iRule["Protocol"].to_s

                        #Thresholds
                        _thresholdMap = Hash.new
                        _thresholdMap["ChecksFailedPercent"] = _iRule["LossThreshold"].to_s
                        _thresholdMap["RoundTripTimeMs"] = _iRule["LatencyThreshold"].to_s
                        _pvtRule["AlertConfiguration"] = _thresholdMap

                        #OnPremAgents
                        _onPremAgents = Array.new
                        _onPremAgentList = _iRule["OnPremAgents"]
                        for j in 0.._onPremAgentList.length-1
                            _onPremAgents.push(_onPremAgentList[j])
                        end
                        _pvtRule["OnPremAgents"] = _onPremAgents

                        #AzureAgents
                        _azureAgents = Array.new
                        _azureAgentsList = _iRule["AzureAgents"]
                        for k in 0.._azureAgentsList.length-1
                            _azureAgents.push(_azureAgentsList[k])
                        end
                        _pvtRule["AzureAgents"] = _azureAgents
                        _ruleList.push(_pvtRule)
                    end
                    _er[:"PrivateRules"] = _ruleList if !_ruleList.empty?
                end

                # Fill MS Peering Rules
                if key == "MSPeeringRules"
                    _ruleList = Array.new
                    for i in 0..rules.length-1
                        _msRule = Hash.new
                        _iRule = rules[i]
                        _msRule["Name"] = _iRule["Name"]
                        _msRule["CircuitName"] = _iRule["CircuitName"]
                        _msRule["Protocol"] = _iRule["Protocol"].to_s
                        _msRule["CircuitResourceId"] = _iRule["CircuitResourceId"]

                        #Thresholds
                        _thresholdMap = Hash.new
                        _thresholdMap["ChecksFailedPercent"] = _iRule["LossThreshold"].to_s
                        _thresholdMap["RoundTripTimeMs"] = _iRule["LatencyThreshold"].to_s
                        _msRule["AlertConfiguration"] = _thresholdMap

                        #OnPremAgents
                        _onPremAgents = Array.new
                        _onPremAgentList = _iRule["OnPremAgents"]
                        for j in 0.._onPremAgentList.length-1
                            _onPremAgents.push(_onPremAgentList[j])
                        end
                        _msRule["OnPremAgents"] = _onPremAgents

                        #Urls
                        _urls = Array.new
                        _urlList = _iRule["UrlList"]
                        for k in 0.._urlList.length-1
                            _urlHash = Hash.new
                            _urlHash["Target"] = _urlList[k]["url"]
                            _urlHash["Port"] = _urlList[k]["port"].to_s
                            _urls.push(_urlHash)
                        end
                        _msRule["URLs"] = _urls
                        _ruleList.push(_msRule)
                    end
                    _er[:"MSPeeringRules"] = _ruleList if !_ruleList.empty?
                end
            end
            _er
        end

    end

    # This class holds the methods for parsing
    # a config sent via DSC into a hash
    class UIConfigParser
        public

        # Only accessible method
        def self.parse(string)
            begin
                _doc = REXML::Document.new(string)
                if _doc.elements.empty? or _doc.root.nil?
                    Logger::logWarn "UI config string converted to nil/empty rexml doc"
                    return nil
                end

                _configVersion = _doc.elements[RootConfigTag].attributes[Version].to_i
                unless _configVersion == 3
                    Logger::logWarn "Config version #{_configVersion} is not supported"
                    return nil
                else
                    Logger::logInfo "Supported version of config #{_configVersion} found"
                end

                _config = _doc.elements[RootConfigTag + "/" + SolnConfigV3Tag]

                if _config.nil? or _config.elements.empty?
                    Logger::logWarn "found nothing for path #{RootConfigTag}/#{SolnConfigV3Tag} in config string"
                    return nil
                end
                
                @agentData = JSON.parse(_config.elements[AgentInfoTag].text())
                @metadata = JSON.parse(_config.elements[MetadataTag].text())

                _h = Hash.new
                _h[KeyMetadata] = @metadata
                _h[KeyNetworks] = getNetworkHashFromJson(_config.elements[NetworkInfoTag].text())
                _h[KeySubnets]  = getSubnetHashFromJson(_config.elements[SubnetInfoTag].text())
                _h[KeyAgents]   = getAgentHashFromJson(_config.elements[AgentInfoTag].text())
                _h[KeyRules]    = getRuleHashFromJson(_config.elements[RuleInfoTag].text()) unless _config.elements[RuleInfoTag].nil?
                _h[KeyEpm]      = getEpmHashFromJson(_config.elements[EpmInfoTag].text()) unless _config.elements[EpmInfoTag].nil?
                _h[KeyER]       = getERHashFromJson(_config.elements[ERInfoTag].text()) unless _config.elements[ERInfoTag].nil?
                
                _h = nil if (_h[KeyNetworks].nil? or _h[KeySubnets].nil? or _h[KeyAgents].nil?)
                if _h == nil
                    Logger::logError "UI Config parsed as nil"
                end
                return _h

            rescue REXML::ParseException => e
                Logger::logError "Got XML parse exception at #{e.line()}, #{e.position()}", Logger::resc
                raise "Got XML parse exception at #{e.line()}, #{e.position()}"
            end
            nil
        end

        private

        RootConfigTag           = "Configuration"
        SolnConfigV3Tag         = "NetworkMonitoringAgentConfigurationV3"
        MetadataTag             = "Metadata"
        NetworkInfoTag          = "NetworkNameToNetworkMap"
        SubnetInfoTag           = "SubnetIdToSubnetMap"
        AgentInfoTag            = "AgentFqdnToAgentMap"
        RuleInfoTag             = "RuleNameToRuleMap"
        EpmInfoTag              = "EPMConfiguration"
        EpmTestInfoTag          = "TestIdToTestMap"
        EpmCMInfoTag            = "ConnectionMonitorIdToInfoMap"
        EpmEndpointInfoTag      = "EndpointIdToEndpointMap"
        EpmAgentInfoTag         = "AgentIdToTestIdsMap"
        ERInfoTag               = "erConfiguration"
        ERPrivatePeeringInfoTag = "erPrivateTestIdToERTestMap";
        ERMSPeeringInfoTag      = "erMSTestIdToERTestMap";
        ERCircuitInfoTag        = "erCircuitIdToCircuitResourceIdMap";
        Version                 = "Version"
        KeyMetadata             = "Metadata"
        KeyNetworks             = "Networks"
        KeySubnets              = "Subnets"
        KeyAgents               = "Agents"
        KeyRules                = "Rules"
        KeyEpm                  = "Epm"
        KeyER                   = "ER"

        # Hash of {AgentID => {AgentContract}}
        @agentData = {}

        # Hash of Metadata
        @metadata = {}

        def self.getCurrentAgentId()
            begin
                _agentId = ""
                _ips = []
                addr_infos = Socket.getifaddrs
                addr_infos.each do |addr_info|
                    if addr_info.addr and (addr_info.addr.ipv4? or addr_info.addr.ipv6?)
                        _ips.push(addr_info.addr.ip_address)
                    end
                end

                @agentData.each do |key, value|
                    next if value.nil? or !(value["IPs"].is_a?Array)
                    value["IPs"].each do |ip|
                        for ipAddr in _ips
                            if ip["Value"] == ipAddr
                                _agentId = key
                                break
                            end
                        end
                    end
                end
                return _agentId
            end
        end

        def self.getNetworkHashFromJson(text)
            begin
                _h = JSON.parse(text)
                _a = Array.new
                _h.each do |key, value|
                    next if value.nil? or value["Subnets"].nil?
                    _network = Hash.new
                    _network["Name"] = key
                    _network["Subnets"] = value["Subnets"]
                    _a << _network
                end
                _a
            rescue JSON::ParserError => e
                Logger::logError "Error in Json Parse in network data: #{e}", Logger::resc
                nil
            end
        end

        def self.getSubnetHashFromJson(text)
            begin
                _h = JSON.parse(text)
            rescue JSON::ParserError => e
                Logger::logError "Error in Json Parse in subnet data: #{e}", Logger::resc
                nil
            end
        end

        def self.getAgentHashFromJson(text)
            begin
                _h = JSON.parse(text)
                _a = Array.new
                _h.each do |key, value|
                    next if value.nil? or !(value["IPs"].is_a?Array)
                    _agent = Hash.new
                    _agent["Guid"] = key
                    _agent["Capability"] = value["Protocol"] unless value["Protocol"].nil?
                    _agent["ResourceId"] = value["ResourceId"] unless value["ResourceId"].nil?
                    _agent["IPs"] = Array.new
                    value["IPs"].each do |ip|
                        _tempIp = Hash.new
                        _tempIp["IP"] = ip["Value"]
                        # Store agent subnet name as string
                        _tempIp["SubnetName"] = ip["Subnet"].to_s
                        _agent["IPs"] << _tempIp
                    end
                    _a << _agent
                end
                _a
            rescue JSON::ParserError => e
                Logger::logError "Error in Json Parse in agent data: #{e}", Logger::resc
                nil
            end
        end

        def self.getRuleHashFromJson(text)
            begin
                _h = JSON.parse(text)
                _a = Array.new
                _h.each do |key, value|
                    next if value.nil? or
                        !(value["ActOn"].is_a?Array) or
                        !(value["Exceptions"].is_a?Array)
                    _rule = Hash.new
                    _rule["Name"] = key
                    _rule["LossThreshold"] = (!value["Threshold"].nil? and value["Threshold"].has_key?("Loss")) ? value["Threshold"]["Loss"] : "-2"
                    _rule["LatencyThreshold"] = (!value["Threshold"].nil? and value["Threshold"].has_key?("Latency")) ? value["Threshold"]["Latency"] : "-2.0"
                    _rule["Protocol"] = value["Protocol"] unless value["Protocol"].nil?
                    _rule["Rules"] = value["ActOn"]
                    _rule["Exceptions"] = value["Exceptions"]
                    _rule["DiscoverPaths"] = value.has_key?("DiscoverPaths") ? value["DiscoverPaths"].to_s : "true"
                    _rule["Description"] = value["Description"]
                    _rule["Enabled"] = value["Enabled"]
                    _rule["Port"] = value["port"]
                    _rule["ListenOnPort"] = value["listenOnPort"]
                    _rule["BiDirectional"] = value["bidirectional"]
                    _rule["Frequency"] = value["frequency"]
                    _rule["WorkspaceResourceId"] = @metadata.has_key?("WorkspaceResourceID") ? @metadata["WorkspaceResourceID"] : String.new
                    _connectionMonitorId = value.has_key?("ConnectionMonitorId") ? value["ConnectionMonitorId"].to_s : String.new

                    # Iterate over ConnectionMonitorInfoMap to get following info
                    if !_connectionMonitorId.empty?
                        _cmMap = _h.has_key?(EpmCMInfoTag) ? _h[EpmCMInfoTag] : Hash.new
                        if !_cmMap.empty?
                            _cmId = _cmMap[_connectionMonitorId.to_s]
                            _rule["CMResourceId"] = _cmId["resourceId"]
                            _rule["IngestionWorkspaceId"] = _cmId["ingestionWorkspaceId"]
                            _rule["WorkspaceAlias"] = _cmId["workspaceAlias"]
                        end
                    end

                    _a << _rule
                end
                _a
            rescue JSON::ParserError => e
                Logger::logError "Error in Json Parse in rule data: #{e}", Logger::resc
                nil
            end
        end

        def self.getEpmHashFromJson(text)
            begin
                _h = JSON.parse(text)
                _epmRules = {"Rules" => []}
                _testAgentMap = getTestAgents(_h[EpmAgentInfoTag])
                _testIds = _h[EpmTestInfoTag]
                _testIds.each_key do |testId|
                    _test = _h[EpmTestInfoTag][testId]
                    _rule = Hash.new
                    _rule["ID"] = testId
                    _rule["Name"] = _test["Name"]
                    _rule["Poll"] = _test["Poll"]
                    _rule["WorkspaceResourceId"] = @metadata.has_key?("WorkspaceResourceID") ? @metadata["WorkspaceResourceID"] : String.new
                    _rule["DiscoverPaths"] = _test.has_key?("DiscoverPaths") ? _test["DiscoverPaths"].to_s : "true"
                    _rule["AppThresholdLoss"] = _test["AppThreshold"].nil? ? "-3" : (_test["AppThreshold"].has_key?("Loss") ? _test["AppThreshold"]["Loss"] : "-2")
                    _rule["AppThresholdLatency"] = _test["AppThreshold"].nil? ? "-3.0" : (_test["AppThreshold"].has_key?("Latency") ? _test["AppThreshold"]["Latency"] : "-2.0")
                    _rule["NetworkThresholdLoss"] = _test["NetworkThreshold"].nil? ? "-3" : (_test["NetworkThreshold"].has_key?("Loss") ? _test["NetworkThreshold"]["Loss"] : "-2")
                    _rule["NetworkThresholdLatency"] = _test["NetworkThreshold"].nil? ? "-3.0" : (_test["NetworkThreshold"].has_key?("Latency") ? _test["NetworkThreshold"]["Latency"] : "-2.0")
                    _rule["ValidStatusCodeRanges"] = _test.has_key?("ValidStatusCodeRanges") ? _test["ValidStatusCodeRanges"] : nil
                    _rule["SourceAgentIds"] = _testAgentMap[testId]
                    _connectionMonitorId = _test.has_key?("ConnectionMonitorId") ? _test["ConnectionMonitorId"].to_s : String.new

                    # Iterate over ConnectionMonitorInfoMap to get following info
                    if !_connectionMonitorId.empty?
                        _cmMap = _h.has_key?(EpmCMInfoTag) ? _h[EpmCMInfoTag] : Hash.new
                        if !_cmMap.empty?
                            _cmId = _cmMap[_connectionMonitorId.to_s]
                            _rule["CMResourceId"] = _cmId["resourceId"]
                            _rule["IngestionWorkspaceId"] = _cmId["ingestionWorkspaceId"]
                            _rule["WorkspaceAlias"] = _cmId["workspaceAlias"]
                        end
                    end

                    # Collect endpoints details
                    _rule["Endpoints"] = []

                    # Get the list of endpoint ids
                    _endpoints = _test["Endpoints"]
                    _endpoints.each do |ep|
                        _endpointHash = Hash.new
                        _endpoint = _h[EpmEndpointInfoTag][ep]
                        _endpointHash["Id"] = ep
                        _endpointHash["Name"] = _endpoint.has_key?("name") ? _endpoint["name"] : String.new
                        _endpointHash["URL"] = _endpoint["url"]
                        _endpointHash["Port"] = _endpoint["port"]
                        _endpointHash["Protocol"] = _endpoint["protocol"]
                        _endpointHash["ListenOnPort"] = _endpoint.has_key?("listenOnPort") ? _endpoint["listenOnPort"] : String.new
                        _endpointHash["Type"] = _endpoint.has_key?("type") ? _endpoint["type"] : String.new
                        _endpointHash["TimeDrift"] = getEndpointTimedrift(testId, ep, _test["Poll"], getWorkspaceId()) #TODO
                        _rule["Endpoints"].push(_endpointHash)
                    end
                    _epmRules["Rules"].push(_rule)
                end

				_epmRules
            rescue JSON::ParserError => e
                Logger::logError "Error in Json Parse in EPM data: #{e}", Logger::resc
                raise "Got exception in EPM parsing: #{e}"
                nil
            end
        end

        def self.getTestAgents(agentTestIdMap)
            begin
                h = agentTestIdMap.each_with_object({}) { |(k,v),g| (v.each{ |item| g.has_key?(item) ? g[item].push(k.to_i) : g[item] ||= [] << k.to_i}) }
                return h
            end
        end

        def self.getWorkspaceId()
            begin
                _workspaceId = @metadata.has_key?("WorkspaceID") ? @metadata["WorkspaceID"] : String.new
                return _workspaceId
            end
        end

        def self.getEndpointTimedrift(testId, endpointId, monitoringInterval, workspaceId)
            begin
                hashString = testId + endpointId + workspaceId
                monIntervalInSecs = monitoringInterval * 60
                hashCode = getHashCode(hashString)
                timeDrift = hashCode % monIntervalInSecs
                return timeDrift.to_s
            end
        end

        def self.getHashCode(str)
            result = 0
            mul = 1
            max_mod = 2**31 - 1

            str.chars.reverse_each do |c|
              result += mul * c.ord
              result %= max_mod
              mul *= 31
            end
            result
        end

        def self.getERHashFromJson(text)
            begin
                _h = JSON.parse(text)
                _agentId = getCurrentAgentId()

                if _agentId.empty?
                    return nil
                else
                    _erRules = {"PrivatePeeringRules" => [], "MSPeeringRules" => []}
                    # Iterate over OnPrem and Azure Agent Lists to check if this agent is part of this test
                    _privateTestMap = _h[ERPrivatePeeringInfoTag]
                    _microsoftTestMap = _h[ERMSPeeringInfoTag]
                    _circuitIdMap = _h[ERCircuitInfoTag]

                    if _privateTestMap.empty? && _microsoftTestMap.empty?
                        Logger::logInfo "ER configuration is not present"
                    end

                    # Private Peering Rules
                    if !_privateTestMap.empty?
                        _privateTestMap.each do |key, value|
                            # Get list of onPremAgents in this test
                            _isAgentPresent = false
                            _privateRule = Hash.new
                            _onPremAgents = value["onPremAgents"]
                            _onPremAgents.each do |x|
                                if x == _agentId
                                    # Append this test to ER Config
                                    _isAgentPresent = true
                                    _privateRule = getERPrivateRuleFromUIConfig(key, value, _circuitIdMap)
                                    break;
                                end
                            end
                            if !_isAgentPresent
                                _azureAgents = value["azureAgents"]
                                _azureAgents.each do |x|
                                    if x == _agentId
                                        _isAgentPresent = true
                                        _privateRule = getERPrivateRuleFromUIConfig(key, value, _circuitIdMap)
                                        break;
                                    end
                                end
                            end
                            if !_privateRule.empty?
                                _erRules["PrivatePeeringRules"].push(_privateRule)
                            end
                        end
                    end

                    # MS Peering Rules
                    if !_microsoftTestMap.empty?
                        _microsoftTestMap.each do |key, value|
                            _microsoftRule = Hash.new
                            _onPremAgents = value["onPremAgents"]
                            _onPremAgents.each do |x|
                                if x == _agentId
                                    # Append this test to ER Config
                                    _isAgentPresent = true
                                    _microsoftRule = getERMicrosoftRuleFromUIConfig(key, value, _circuitIdMap)
                                    break;
                                end
                            end
                            if !_microsoftRule.empty?
                                _erRules["MSPeeringRules"].push(_microsoftRule)
                            end
                        end
                    end
                    _erRules
                end
            rescue JSON::ParserError => e
                Logger::logError "Error in Json Parse in ER data: #{e}", Logger::resc
                nil
            end 
        end

        def self.getERPrivateRuleFromUIConfig(key, value, _circuitIdMap)
            _ruleHash = Hash.new
            _ruleHash["Name"] = key
            _ruleHash["Protocol"] = value["protocol"]
            _ruleHash["CircuitId"] = value["circuitId"]
            _ruleHash["LossThreshold"] = (!value["threshold"].nil? and value["threshold"].has_key?("loss")) ? value["threshold"]["loss"] : "-2"
            _ruleHash["LatencyThreshold"] = (!value["threshold"].nil? and value["threshold"].has_key?("latency")) ? value["threshold"]["latency"] : "-2.0"
            _ruleHash["CircuitName"] = value["circuitName"]
            _ruleHash["vNetName"]= value["vNet"]
            _ruleHash["ConnectionResourceId"]= value["connectionResourceId"]
            _ruleHash["CircuitResourceId"] = _circuitIdMap[value["circuitId"]]
            _ruleHash["OnPremAgents"] = value["onPremAgents"]
            _ruleHash["AzureAgents"] = value["azureAgents"]
            return _ruleHash
        end

        def self.getERMicrosoftRuleFromUIConfig(key, value, _circuitIdMap)
            _ruleHash = Hash.new
            _ruleHash["Name"] = key
            _ruleHash["CircuitName"] = value["circuitName"]
            _ruleHash["CircuitId"] = value["circuitId"]
            _ruleHash["Protocol"] = value["protocol"]
            _ruleHash["CircuitResourceId"] = _circuitIdMap[value["circuitId"]]
            _ruleHash["LossThreshold"] = (!value["threshold"].nil? and value["threshold"].has_key?("loss")) ? value["threshold"]["loss"] : "-2"
            _ruleHash["LatencyThreshold"] = (!value["threshold"].nil? and value["threshold"].has_key?("latency")) ? value["threshold"]["latency"] : "-2.0"
            _ruleHash["UrlList"] = value["urlList"]
            _ruleHash["OnPremAgents"] = value["onPremAgents"]
            return _ruleHash
        end
    end

    # Only function needed to be called from this module
    def self.GetAgentConfigFromUIConfig(uiXml)
        _uiHash = UIConfigParser.parse(uiXml)
        AgentConfigCreator.resetErrorCheck()
        _agentJson = AgentConfigCreator.createJsonFromUIConfigHash(_uiHash)
        _errorStr = AgentConfigCreator.getErrorSummary()
        return _agentJson, _errorStr
    end

end

# NPM Contracts verification for data being uploaded
module NPMContract
    DATAITEM_AGENT                    = "agent"
    DATAITEM_PATH                     = "path"
    DATAITEM_DIAG                     = "diagnostics"
    DATAITEM_ENDPOINT_HEALTH          = "endpointHealth"
    DATAITEM_ENDPOINT_MONITORING      = "endpointMonitoringData"
    DATAITEM_ENDPOINT_DIAGNOSTICS     = "endpointDiagnostics"
    DATAITEM_EXROUTE_MONITORING       = "expressrouteMonitoringData"
    DATAITEM_CONNECTIONMONITOR_TEST   = "connectionMonitorTestResult"
    DATAITEM_CONNECTIONMONITOR_PATH   = "connectionMonitorPathData"
    DATAITEM_AGENT_DIAGNOSTICS        = "agentDiagnostics"


    DATAITEM_VALID = 1
    DATAITEM_ERR_INVALID_FIELDS = 2
    DATAITEM_ERR_INVALID_TYPE = 3

    CONTRACT_AGENT_DATA_KEYS = ["AgentFqdn",
                                "AgentIP",
                                "AgentCapability",
                                "SubnetId",
                                "PrefixLength",
                                "AddressType",
                                "SubType",
                                "TimeGenerated",
                                "OSType",
                                "NPMAgentEnvironment"]

    CONTRACT_AGENT_DIAGNOSTICS_KEYS = ["SubType",
                                       "TimeGenerated",
                                       "NotificationCode",
                                       "NotificationType",
                                       "Computer"]

    CONTRACT_PATH_DATA_KEYS  = ["SourceNetwork",
                                "SourceNetworkNodeInterface",
                                "SourceSubNetwork",
                                "DestinationNetwork",
                                "DestinationNetworkNodeInterface",
                                "DestinationSubNetwork",
                                "RuleName",
                                "TimeSinceActive",
                                "LossThreshold",
                                "LatencyThreshold",
                                "LossThresholdMode",
                                "LatencyThresholdMode",
                                "SubType",
                                "HighLatency",
                                "MedianLatency",
                                "LowLatency",
                                "LatencyHealthState",
                                "Loss",
                                "LossHealthState",
                                "Path",
                                "Computer",
                                "TimeGenerated",
                                "Protocol",
                                "MinHopLatencyList",
                                "MaxHopLatencyList",
                                "AvgHopLatencyList",
                                "TraceRouteCompletionTime"]

    CONTRACT_DIAG_DATA_KEYS  = ["SubType",
                                "Message"]

    CONTRACT_ENDPOINT_HEALTH_DATA_KEYS  =  ["SubType",
                                            "TestName",
                                            "ServiceTestId",
                                            "ConnectionMonitorResourceId",
                                            "Target",
                                            "Port",
                                            "EndpointId",
                                            "Protocol",
                                            "TimeSinceActive",
                                            "ServiceResponseTime",
                                            "ServiceLossPercent",
                                            "ServiceLossHealthState",
                                            "ServiceResponseHealthState",
                                            "ResponseCodeHealthState",
                                            "ServiceResponseThresholdMode",
                                            "ServiceResponseThreshold",
                                            "ServiceResponseCode",
                                            "Loss",
                                            "LossHealthState",
                                            "LossThresholdMode",
                                            "LossThreshold",
                                            "NetworkTestEnabled",
                                            "MedianLatency",
                                            "HighLatency",
                                            "LowLatency",
                                            "LatencyThresholdMode",
                                            "LatencyThreshold",
                                            "LatencyHealthState",
                                            "TimeGenerated",
                                            "Computer"]

    CONTRACT_ENDPOINT_PATH_DATA_KEYS = ["SubType",
                                        "TestName",
                                        "ServiceTestId",
                                        "ConnectionMonitorResourceId",
                                        "Target",
                                        "Port",
                                        "TimeSinceActive",
                                        "EndpointId",
                                        "SourceNetworkNodeInterface",
                                        "DestinationNetworkNodeInterface",
                                        "Path",
                                        "Loss",
                                        "NetworkTestEnabled",
                                        "HighLatency",
                                        "MedianLatency",
                                        "LowLatency",
                                        "LossHealthState",
                                        "LatencyHealthState",
                                        "LossThresholdMode",
                                        "LossThreshold",
                                        "LatencyThresholdMode",
                                        "LatencyThreshold",
                                        "Computer",
                                        "Protocol",
                                        "MinHopLatencyList",
                                        "MaxHopLatencyList",
                                        "AvgHopLatencyList",
                                        "TraceRouteCompletionTime",
                                        "TimeGenerated"]

    CONTRACT_ENDPOINT_DIAG_DATA_KEYS = ["SubType",
                                        "TestName",
                                        "ServiceTestId",
                                        "ConnectionMonitorResourceId",
                                        "Target",
                                        "NotificationCode",
                                        "EndpointId",
                                        "TimeGenerated",
                                        "Computer"]

    CONTRACT_EXROUTE_MONITOR_DATA_KEYS =   ["SubType",
                                            "TimeGenerated",
                                            "Circuit",
                                            "ComputerEnvironment",
                                            "vNet",
                                            "Target",
                                            "PeeringType",
                                            "CircuitResourceId",
                                            "ConnectionResourceId",
                                            "Path",
                                            "SourceNetworkNodeInterface",
                                            "DestinationNetworkNodeInterface",
                                            "Loss",
                                            "HighLatency",
                                            "MedianLatency",
                                            "LowLatency",
                                            "LossHealthState",
                                            "LatencyHealthState",
                                            "RuleName",
                                            "TimeSinceActive",
                                            "LossThreshold",
                                            "LatencyThreshold",
                                            "LossThresholdMode",
                                            "LatencyThresholdMode",
                                            "Computer",
                                            "Protocol",
                                            "MinHopLatencyList",
                                            "MaxHopLatencyList",
                                            "AvgHopLatencyList",
                                            "TraceRouteCompletionTime",
                                            "DiagnosticHop",
                                            "DiagnosticHopLatency"]

    CONTRACT_CONNECTIONMONITOR_TEST_RESULT_KEYS =  ["SubType",
                                                    "RecordId",
                                                    "Computer",
                                                    "ConnectionMonitorResourceId",
                                                    "TimeCreated",
                                                    "TestGroupName",
                                                    "TestConfigurationName",
                                                    "SourceType",
                                                    "SourceResourceId",
                                                    "SourceAddress",
                                                    "SourceName",
                                                    "SourceIP",
                                                    "DestinationType",
                                                    "DestinationResourceId",
                                                    "DestinationAddress",
                                                    "DestinationName",
                                                    "DestinationAgentId",
                                                    "Protocol",
                                                    "DestinationPort",
                                                    "DestinationIP",
                                                    "ChecksTotal",
                                                    "ChecksFailed",
                                                    "ChecksFailedPercentThreshold",
                                                    "RoundTripTimeMsThreshold",
                                                    "MinRoundTripTimeMs",
                                                    "MaxRoundTripTimeMs",
                                                    "AvgRoundTripTimeMs",
                                                    "TestResult",
                                                    "TestResultCriterion",
                                                    "AdditionalData",
                                                    "IngestionWorkspaceResourceId"]

    CONTRACT_CONNECTIONMONITOR_PATH_DATA_KEYS =    ["SubType",
                                                    "RecordId",
                                                    "Computer",
                                                    "TopologyId",
                                                    "ConnectionMonitorResourceId",
                                                    "TimeCreated",
                                                    "TestGroupName",
                                                    "TestConfigurationName",
                                                    "SourceType",
                                                    "SourceResourceId",
                                                    "SourceAddress",
                                                    "SourceName",
                                                    "SourceIP",
                                                    "DestinationType",
                                                    "DestinationResourceId",
                                                    "DestinationAddress",
                                                    "DestinationName",
                                                    "DestinationIP",
                                                    "DestinationAgentId",
                                                    "ChecksTotal",
                                                    "ChecksFailed",
                                                    "ChecksFailedPercentThreshold",
                                                    "RoundTripTimeMsThreshold",
                                                    "MinRoundTripTimeMs",
                                                    "MaxRoundTripTimeMs",
                                                    "AvgRoundTripTimeMs",
                                                    "HopAddresses",
                                                    "HopTypes",
                                                    "HopLinkTypes",
                                                    "HopResourceIds",
                                                    "Issues",
                                                    "Hops",
                                                    "DestinationPort",
                                                    "Protocol",
                                                    "PathTestResult",
                                                    "PathTestResultCriterion",
                                                    "AdditionalData",
                                                    "IngestionWorkspaceResourceId",
                                                    "UploadDirectly"]

    def self.IsValidDataitem(item, itemType)
        _contract=[]

        if itemType == DATAITEM_AGENT
            _contract = CONTRACT_AGENT_DATA_KEYS
        elsif itemType == DATAITEM_PATH
            _contract = CONTRACT_PATH_DATA_KEYS
        elsif itemType == DATAITEM_DIAG
            _contract = CONTRACT_DIAG_DATA_KEYS
        elsif itemType == DATAITEM_ENDPOINT_HEALTH
            _contract = CONTRACT_ENDPOINT_HEALTH_DATA_KEYS
        elsif itemType == DATAITEM_ENDPOINT_MONITORING
            _contract = CONTRACT_ENDPOINT_PATH_DATA_KEYS
        elsif itemType == DATAITEM_ENDPOINT_DIAGNOSTICS
            _contract = CONTRACT_ENDPOINT_DIAG_DATA_KEYS
        elsif itemType == DATAITEM_EXROUTE_MONITORING
            _contract = CONTRACT_EXROUTE_MONITOR_DATA_KEYS
        elsif itemType == DATAITEM_CONNECTIONMONITOR_TEST
            _contract = CONTRACT_CONNECTIONMONITOR_TEST_RESULT_KEYS
        elsif itemType == DATAITEM_CONNECTIONMONITOR_PATH
            _contract = CONTRACT_CONNECTIONMONITOR_PATH_DATA_KEYS
        elsif itemType == DATAITEM_AGENT_DIAGNOSTICS
            _contract = CONTRACT_AGENT_DIAGNOSTICS_KEYS
        end

        return DATAITEM_ERR_INVALID_TYPE, nil if _contract.empty?

        item.keys.each do |k|
            return DATAITEM_ERR_INVALID_FIELDS, k if !_contract.include?(k)
        end

        return DATAITEM_VALID, nil
    end

end

