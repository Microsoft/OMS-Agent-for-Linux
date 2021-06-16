# frozen_string_literal: true

module OMS

  class Configuration
    require 'openssl'
    require 'uri'

    require_relative 'omslog'

    @@ConfigurationLoaded = false

    @@Cert = nil
    @@Key = nil

    @@AgentId = nil
    @@WorkspaceId = nil
    @@ODSEndpoint = nil
    @@DiagnosticEndpoint = nil
    @@GetBlobODSEndpoint = nil
    @@NotifyBlobODSEndpoint = nil
    @@OmsCloudId = nil
    @@AgentGUID = nil
    @@URLTLD = nil
    @@LogFacility = nil
    @@AzureResourceId = nil
    @@AzureRegion = nil
    @@AzureIMDSEndpoint = "http://169.254.169.254/metadata/instance?api-version=2017-12-01"
    @@AzureResIDThreadLock = Mutex.new
    @@ProxyConfig = nil
    @@ProxyConfigFilePath = "/etc/opt/microsoft/omsagent/proxy.conf"
    @@UUID = nil
    @@TopologyInterval = 1200 # set default (20m)
    @@TelemetryInterval = 300 # set default (5m)
    @@HybridRPConfFile = "/lib/systemd/system.conf.d/azcmagent.conf"
    @@HyrbidRPIMDSPath = "/metadata/instance"
    @@HybridRPAPIVersion = "2019-08-15"

    class << self

      # test the onboard file existence
      def test_onboard_file(file_name)
        if !File.file?(file_name)
          OMS::Log.error_once("Could not find #{file_name} Make sure to onboard.")
          return false
        end

        if !File.readable?(file_name)
          OMS::Log.error_once("Could not read #{file_name} Check that the read permissions are set for the omsagent user")
          return false
        end

        return true
      end

      def get_proxy_config(proxy_conf_path)
        old_proxy_conf_path = '/etc/opt/microsoft/omsagent/conf/proxy.conf'
        if !File.exist?(proxy_conf_path) and File.exist?(old_proxy_conf_path)
          proxy_conf_path = old_proxy_conf_path
        end

        begin
          proxy_config = parse_proxy_config(File.read(proxy_conf_path))
        rescue SystemCallError # Error::ENOENT
          return {}
        end

        if proxy_config.nil?
          OMS::Log.error_once("Failed to parse the proxy configuration in '#{proxy_conf_path}'")
          return {}
        end

        return proxy_config
      end

      def parse_proxy_config(proxy_conf_str)
          # Remove the http(s) protocol
          proxy_conf_str = proxy_conf_str.gsub(/^(https?:\/\/)?/, "")

          # Check for unsupported protocol
          if proxy_conf_str[/^[a-z]+:\/\//]
            return nil
          end

          re = /^(?:(?<user>[^:]+):(?<pass>[^@]+)@)?(?<addr>[^:@]+)(?::(?<port>\d+))?$/ 
          matches = re.match(proxy_conf_str)
          if matches.nil? or matches[:addr].nil? 
            return nil
          end
          # Convert nammed matches to a hash
          Hash[ matches.names.map{ |name| name.to_sym}.zip( matches.captures ) ]
      end
      
      def get_azure_region_from_imds()
          begin
            uri = URI.parse(@@AzureIMDSEndpoint)
            http_get_req = Net::HTTP::Get.new(uri, initheader = {'Metadata' => 'true'})

            http_req = Net::HTTP.new(uri.host, uri.port)

            http_req.open_timeout = 3
            http_req.read_timeout = 2

            res = http_req.start() do |http|
              http.request(http_get_req)
            end

            imds_instance_json = JSON.parse(res.body)

            return nil if !imds_instance_json.has_key?("compute") || imds_instance_json['compute'].empty? #classic vm

            imds_instance_json_compute = imds_instance_json['compute']
            return nil unless imds_instance_json_compute.has_key?("location")
            return nil if imds_instance_json_compute['location'].empty?
            return imds_instance_json_compute['location']
          rescue => e
            # this may be a container instance or a non-Azure VM
            return nil
          end
      end

      def get_azure_resid_from_imds()
          begin
            uri = URI.parse(@@AzureIMDSEndpoint)
            http_get_req = Net::HTTP::Get.new(uri, initheader = {'Metadata' => 'true'})

            http_req = Net::HTTP.new(uri.host, uri.port)

            http_req.open_timeout = 3
            http_req.read_timeout = 2

            res = http_req.start() do |http|
              http.request(http_get_req)
            end

            imds_instance_json = JSON.parse(res.body)

            return nil if !imds_instance_json.has_key?("compute") || imds_instance_json['compute'].empty? #classic vm

            imds_instance_json_compute = imds_instance_json['compute']

            #guard from missing keys
            return nil unless imds_instance_json_compute.has_key?("subscriptionId") && imds_instance_json_compute.has_key?("resourceGroupName") && imds_instance_json_compute.has_key?("name") && imds_instance_json_compute.has_key?("vmScaleSetName")

            #guard from blank values
            return nil if imds_instance_json_compute['subscriptionId'].empty? || imds_instance_json_compute['resourceGroupName'].empty? || imds_instance_json_compute['name'].empty?

            azure_resource_id = '/subscriptions/' + imds_instance_json_compute['subscriptionId'] + '/resourceGroups/' + imds_instance_json_compute['resourceGroupName'] + '/providers/Microsoft.Compute/'

            if (imds_instance_json_compute['vmScaleSetName'].empty?)
              azure_resource_id = azure_resource_id + 'virtualMachines/' + imds_instance_json_compute['name']
            else
              azure_resource_id = azure_resource_id + 'virtualMachineScaleSets/' + imds_instance_json_compute['vmScaleSetName'] + '/virtualMachines/' + imds_instance_json_compute['name'].split('_')[-1]
            end

            return azure_resource_id

          rescue => e
            # this may be a container instance or a non-Azure VM
            OMS::Log.warn_once("Could not fetch Azure Resource ID from IMDS, Reason: #{e}")
            return nil
          end
      end

      def get_azure_resid_from_hybridagent()
        begin
          #check if the file containing hybrid imds endpoint exists?
          if File.file?(@@HybridRPConfFile)
            OMS::Log.info_once("Using The HybridRP IMDS_Endpoint to fetch resource id")
            data = File.read(@@HybridRPConfFile)
            azureHybridIMDSEndpoint = data.scan(/"IMDS_ENDPOINT=.*"?/)[0]
            if azureHybridIMDSEndpoint.nil?
              OMS::Log.warn_once("Failed to read the IMDS Endpoint from #{@@HybridRPConfFile}. Failed to fetch azure resource id")
              return nil
            end

            #Subbing localhost with 127.0.0.1 because Ruby's resolv-replace module (imported in oms_common.rb fails to correctly resolve localhost)
            azureHybridIMDSEndpoint = azureHybridIMDSEndpoint.split("=")[1][0..-2].sub("localhost","127.0.0.1")
            azureHybridIMDSEndpoint += @@HyrbidRPIMDSPath + "?api-version=" + @@HybridRPAPIVersion

            uri = URI.parse(azureHybridIMDSEndpoint)
            http_get_req = Net::HTTP::Get.new(uri, initheader = {'Metadata' => 'true'})
            http_req = Net::HTTP.new(uri.host, uri.port)
            http_req.open_timeout = 3
            http_req.read_timeout = 2
            res = http_req.start() do |http|
              http.request(http_get_req)
            end

            imds_instance_json = JSON.parse(res.body)

            return nil if !imds_instance_json.has_key?("compute") || imds_instance_json['compute'].empty? #classic vm
            imds_instance_json_compute = imds_instance_json['compute']
            
            return nil if !imds_instance_json_compute.has_key?("resourceID") || imds_instance_json_compute['resourceID'].empty? 
            azure_resource_id = imds_instance_json_compute['resourceID']
            
            return azure_resource_id
          else
            #config file containing HyrbidRP IMDS endpoint not found.
            OMS::Log.warn_once("Could not find the config file #{@@HybridRPConfFile} containing the HybridRP IMDS Endpoint. Failed to fetch azure resource id.")
            return nil
          end
        rescue => e
          # this may be a container instance or a non Hybrid Agent VM
          OMS::Log.warn_once("Could not fetch Azure Resource ID from HybridRP IMDS, Reason: #{e}")
          return nil
        end
      end

      def update_azure_resource_id()
          retries=1
          max_retries=3

          loop do
            break if retries > max_retries
            #Check if this is a non azure Hybrid Agent VM
            if system("systemctl status himdsd 1>/dev/null 2>&1")
              OMS::Log.info_once("This is an Azure Arc VM")
              azure_resource_id = get_azure_resid_from_hybridagent()
            else
              azure_resource_id = get_azure_resid_from_imds()
            end
            if azure_resource_id.nil?
              sleep (retries * 120)
              retries += 1
              next
            end

            @@AzureResourceId = azure_resource_id unless @@AzureResourceId == azure_resource_id
            retries=1 #reset
            sleep 60
          end

          OMS::Log.warn_once("Exceeded max attempts to fetch Azure Resource ID, killing the thread")
          return #terminate
      end

      # load the configuration from the configuration file, cert, and key path
      def load_configuration(conf_path, cert_path, key_path)
        return true if @@ConfigurationLoaded
        return false if !test_onboard_file(conf_path) or !test_onboard_file(cert_path) or !test_onboard_file(key_path)

        @@ProxyConfig = get_proxy_config(@@ProxyConfigFilePath)

        endpoint_lines = IO.readlines(conf_path).select{ |line| line.start_with?("OMS_ENDPOINT")}
        if endpoint_lines.size == 0
          OMS::Log.error_once("Could not find OMS_ENDPOINT setting in #{conf_path}")
          return false
        elsif endpoint_lines.size > 1
          OMS::Log.warn_once("Found more than one OMS_ENDPOINT setting in #{conf_path}, will use the first one.")
        end

        begin
          endpoint_url = endpoint_lines[0].split("=")[1].strip
          @@ODSEndpoint = URI.parse( endpoint_url )
          @@GetBlobODSEndpoint = @@ODSEndpoint.clone
          @@GetBlobODSEndpoint.path = '/ContainerService.svc/GetBlobUploadUri'
          @@NotifyBlobODSEndpoint = @@ODSEndpoint.clone
          @@NotifyBlobODSEndpoint.path = '/ContainerService.svc/PostBlobUploadNotification'
        rescue => e
          OMS::Log.error_once("Error parsing endpoint url. #{e}")
          return false
        end

        begin
          diagnostic_endpoint_lines = IO.readlines(conf_path).select{ |line| line.start_with?("DIAGNOSTIC_ENDPOINT=")}
          if diagnostic_endpoint_lines.size == 0
            # Endpoint to be inferred from @@ODSEndpoint
            @@DiagnosticEndpoint = @@ODSEndpoint.clone
            @@DiagnosticEndpoint.path = '/DiagnosticsDataService.svc/PostJsonDataItems'
          else
            if diagnostic_endpoint_lines.size > 1
              OMS::Log.warn_once("Found more than one DIAGNOSTIC_ENDPOINT setting in #{conf_path}, will use the first one.")
            end
            diagnostic_endpoint_url = diagnostic_endpoint_lines[0].split("=")[1].strip
            @@DiagnosticEndpoint = URI.parse( diagnostic_endpoint_url )
          end
        rescue => e
          OMS::Log.error_once("Error obtaining diagnostic endpoint url. #{e}")
          return false
        end

        agentid_lines = IO.readlines(conf_path).select{ |line| line.start_with?("AGENT_GUID")}
        if agentid_lines.size == 0
          OMS::Log.error_once("Could not find AGENT_GUID setting in #{conf_path}")
          return false
        elsif agentid_lines.size > 1
          OMS::Log.warn_once("Found more than one AGENT_GUID setting in #{conf_path}, will use the first one.")
        end

        begin
          @@AgentId = agentid_lines[0].split("=")[1].strip
        rescue => e
          OMS::Log.error_once("Error parsing agent id. #{e}")
          return false
        end

        File.open(conf_path).each_line do |line|
          if line =~ /^WORKSPACE_ID/
            @@WorkspaceId = line.sub("WORKSPACE_ID=","").strip
          end
          if line =~ /AZURE_RESOURCE_ID/
            # We have contract with AKS team about how to pass AKS specific resource id.
            # As per contract, AKS team before starting the agent will set environment variable 
            # 'customResourceId'
            @@AzureResourceId = ENV['customResourceId']
            
            # Only if environment variable is empty/nil load it from imds and refresh it periodically.
            if @@AzureResourceId.nil? || @@AzureResourceId.empty?
              @@AzureResourceId = line.sub("AZURE_RESOURCE_ID=","").strip
              if @@AzureResourceId.include? "Microsoft.ContainerService"
                OMS::Log.info_once("Azure resource id in configuration file is for AKS. It will be used")
              else
                Thread.new(&method(:update_azure_resource_id)) if @@AzureResIDThreadLock.try_lock
              end
            else
              OMS::Log.info_once("There is non empty value set for overriden-resourceId environment variable. It will be used")
            end
          end
          if line =~ /OMSCLOUD_ID/
            @@OmsCloudId = line.sub("OMSCLOUD_ID=","").strip
          end
          if line =~ /^AGENT_GUID/
            @@AgentGUID = line.sub("AGENT_GUID=","").strip
          end
          if line =~ /^URL_TLD/
            @@URLTLD = line.sub("URL_TLD=","").strip
          end
          if line =~ /^LOG_FACILITY/
            @@LogFacility = line.sub("LOG_FACILITY=","").strip
          end
          if line =~ /UUID/
            uuid_str = line.sub("UUID=","").strip
            uuid_regex = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/
            if uuid_str =~ uuid_regex
              @@UUID = uuid_str
            else
              @@UUID = "00000000-0000-0000-0000-000000000000" 
            end
          end
        end

        begin
          raw = File.read cert_path
          @@Cert = OpenSSL::X509::Certificate.new raw
          raw = File.read key_path
          @@Key  = OpenSSL::PKey::RSA.new raw
        rescue => e
          OMS::Log.error_once("Error loading certs: #{e}")
          return false
        end
    
        @@AzureRegion = get_azure_region_from_imds()
        if @@AzureRegion.nil? || @@AzureRegion.empty?
          OMS::Log.warn_once("Azure region value is not set. This must be onpremise machine")
          @@AzureRegion = "OnPremise"
        end
        
        @@ConfigurationLoaded = true
        return true
      end # load_configuration

      def set_request_intervals(topology_interval, telemetry_interval)
        @@TopologyInterval = topology_interval
        @@TelemetryInterval = telemetry_interval
        OMS::Log.info_once("OMS agent management service topology request interval now #{@@TopologyInterval}")
        OMS::Log.info_once("OMS agent management service telemetry request interval now #{@@TelemetryInterval}")
      end

      # Check whether DSC has been disabled (which prevents automatic config management)
      def is_dsc_disabled
        begin
          return File.exist?("/etc/opt/omi/conf/omsconfig/omshelper_disable")
        rescue => e
          OMS::Log.error_once("Failed to get DSC enabled/disabled status. #{e}")
        end
      end

      def cert
        @@Cert
      end # getter cert

      def key
        @@Key
      end # getter key

      def workspace_id
        @@WorkspaceId
      end # getter workspace_id

      def agent_id
        @@AgentId
      end # getter agent_id

      def ods_endpoint
        @@ODSEndpoint
      end # getter ods_endpoint

      def diagnostic_endpoint
        @@DiagnosticEndpoint
      end # getter diagnostic_endpoint

      def get_blob_ods_endpoint
        @@GetBlobODSEndpoint
      end # getter get_blob_ods_endpoint

      def notify_blob_ods_endpoint
        @@NotifyBlobODSEndpoint
      end # getter notify_blob_ods_endpoint

      def azure_resource_id
        @@AzureResourceId
      end

      def omscloud_id
        @@OmsCloudId
      end

      def agent_guid
        @@AgentGUID
      end # getter agent_guid

      def url_tld
        @@URLTLD
      end # getter url_tld

      def log_facility
        @@LogFacility
      end # getter log_facility

      def uuid
        @@UUID
      end # getter for VM uuid

      def azure_region
        @@AzureRegion
      end

      def topology_interval
        @@TopologyInterval
      end

      def telemetry_interval
        @@TelemetryInterval
      end

    end # Class methods
        
  end # class Common
end # module OMS
