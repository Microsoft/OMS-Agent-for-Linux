module Fluent

  class OutChangeTrackingFile < BufferedOutput

    Plugin.register_output('out.oms.changetracking.file', self)
	
    # Endpoint URL ex. localhost.local/api/

    def initialize
      super
	  
      require 'base64'
      require 'digest'
      require 'json'
      require 'net/http'
      require 'net/https'
      require 'openssl'
      require 'rexml/document'
      require 'securerandom'
      require 'socket'
      require 'uri'
      require 'cgi'
      require_relative 'omslog'
      require_relative 'oms_configuration'
      require_relative 'oms_common'
      require_relative 'agent_telemetry_script'
    end

    config_param :omsadmin_conf_path, :string, :default => '/etc/opt/microsoft/omsagent/conf/omsadmin.conf'
    config_param :cert_path, :string, :default => '/etc/opt/microsoft/omsagent/certs/oms.crt'
    config_param :key_path, :string, :default => '/etc/opt/microsoft/omsagent/certs/oms.key'
    config_param :proxy_conf_path, :string, :default => '/etc/opt/microsoft/omsagent/proxy.conf'
    config_param :compress, :bool, :default => true
    config_param :PrimaryContentLocation, :string, :default => ''
    config_param :SecondaryContentLocation, :string, :default => ''
    config_param :ContentLocationDescription, :string, :default => ''
    config_param :buffer_path, :string, :default => ''

    @@ContentlocationUri = ''
    @@LastContentLocationUri = ''
    @@ContentlocationUriResourceId = ''
    @@PrimaryContentLocationAccessToken = ''
    @@SecondaryContentLocationAccessToken = ''
    @@ContentLocationCacheFileName = "contentlocationcache.cache"

    # Set/Get methods for use in tests
    def get_ContentlocationUri
       return @@ContentlocationUri
    end 
    def set_ContentlocationUri(contentlocationUri)
       @@ContentlocationUri = contentlocationUri
    end 
    def get_PrimaryContentLocationAccessToken
       return @@PrimaryContentLocationAccessToken
    end 
    def set_PrimaryContentLocationAccessToken(token)
       @@PrimaryContentLocationAccessToken = token
    end 
    def get_SecondaryContentLocationAccessToken
       return @@SecondaryContentLocationAccessToken
    end 
    def set_SecondaryContentLocationAccessToken(token)
       return @@SecondaryContentLocationAccessToken = token
    end 
    def get_PrimaryContentLocation
       return @@PrimaryContentLocation
    end 
    def set_PrimaryContentLocation(primaryContentLocation)
        @@PrimaryContentLocation = primaryContentLocation
    end 
    def get_SecondaryContentLocation
       return @@SecondaryContentLocation
    end 
    def set_SecondaryContentLocation(secondryContentLocation)
        @@SecondaryContentLocation = secondryContentLocation
    end 
    def get_ContentlocationUriResourceId
       return @@ContentlocationUriResourceId
    end 
    def set_ContentlocationUriResourceId(resourceId)
        @@ContentlocationUriResourceId = resourceId
    end 

    def configure(conf)
      s = conf.add_element("secondary")
      s["type"] = ChunkErrorHandler::SecondaryName

      super
      if !@PrimaryContentLocation.nil? and !@PrimaryContentLocation.empty? and @PrimaryContentLocation.include? "http" or @PrimaryContentLocation.include? "https"
         decodedUri = CGI::unescapeHTML(@PrimaryContentLocation)
         urlDetails = decodedUri.split('?')
         if !urlDetails.nil? and urlDetails.length == 2
            @@ContentlocationUri = urlDetails[0].strip
            @@PrimaryContentLocationAccessToken = urlDetails[1]
            @@ContentlocationUriResourceId = @ContentLocationDescription
         end
      end
      if !@SecondaryContentLocation.nil? and !@SecondaryContentLocation.empty? and @SecondaryContentLocation.include? "http" or @SecondaryContentLocation.include? "https"
         decodedUri = CGI::unescapeHTML(@SecondaryContentLocation)
         urlDetails = decodedUri.split('?')
         if !urlDetails.nil? and urlDetails.length == 2
            @@SecondaryContentLocationAccessToken = urlDetails[1].strip
         end
      end
    end

    def start
      super
      @proxy_config = OMS::Configuration.get_proxy_config(@proxy_conf_path)
      @sha256 = Digest::SHA256.new
      @log.debug "buffer_path : #{@buffer_path}"
      if !@buffer_path.empty?
         contentlocationfilepath = File.dirname(@buffer_path) + '/' + @@ContentLocationCacheFileName

         @log.debug "contentlocationfilepath : #{contentlocationfilepath}"
         if File.exists?(contentlocationfilepath)
            content = File.open(contentlocationfilepath, &:gets)
            if !content.nil? and !content.empty?
               @@LastContentLocationUri = content.strip
            end
         end
      end
      @log.debug "LastContentLocationUri : #{@@LastContentLocationUri}"
    end

    def shutdown
      if (!@buffer_path.empty? && !(defined?(file_path)).nil? && !file_path.nil?)
         contentlocationfilepath = File.dirname(@buffer_path) + '/' + @@ContentLocationCacheFileName
         File.open(file_path, "w+", 0644) do |f| # Open file
              f.puts "#{@@ContentlocationUri}"
         end
      @log.debug "LastContentLocationUri written to : #{contentlocationfilepath}"
	  end
      super
    end

    ####################################################################################################
    # Methods
    ####################################################################################################

    # create a HTTP request to PUT blob
    # parameters:
    #   uri: URI. blob URI
    #   msg: string. body of the request
    #   file_path: string. file path
    # returns:
    #   HTTPRequest. blob PUT request
    def create_blob_put_request(uri, msg, request_id, file_path = nil)
      headers = {}

      headers[OMS::CaseSensitiveString.new("x-ms-meta-TimeZoneid")] = OMS::Common.get_current_timezone
      headers[OMS::CaseSensitiveString.new("x-ms-meta-ComputerName")] = OMS::Common.get_hostname
      if !file_path.nil?
        headers[OMS::CaseSensitiveString.new("x-ms-meta-FilePath")] = file_path
      end

      azure_resource_id = OMS::Configuration.azure_resource_id
      if !azure_resource_id.to_s.empty?
        headers[OMS::CaseSensitiveString.new("x-ms-AzureResourceId")] = azure_resource_id
      end
      
      omscloud_id = OMS::Configuration.omscloud_id
      if !omscloud_id.to_s.empty?
        headers[OMS::CaseSensitiveString.new("x-ms-OMSCloudId")] = omscloud_id
      end

      uuid = OMS::Configuration.uuid
      if !uuid.to_s.empty?
        headers[OMS::CaseSensitiveString.new("x-ms-UUID")] = uuid
      end

      headers[OMS::CaseSensitiveString.new("X-Request-ID")] = request_id

      headers["Content-Type"] = "application/octet-stream"
      headers["Content-Length"] = msg.bytesize.to_s

      req = Net::HTTP::Put.new(uri.request_uri, headers)
      req.body = msg
      return req
    rescue OMS::RetryRequestException => e
        OMS::Log.error_once("HTTP error for Request-ID: #{request_id} Error: #{e}")
        raise e.message, "Request-ID: #{request_id}"
    end # create_blob_put_request

    # append data to the blob
    # parameters:
    #   uri: URI. blob URI
    #   msgs: string[]. messages
    #   file_path: string. file path
    def append_blob(uri, msgs, file_path)
      if msgs.size == 0
        return 0
      end

      # concatenate the messages
      msg = ''
      msgs.each { |s| msg << "#{s}\r\n" if s.to_s.length > 0 }
      dataSize = msg.length

      if dataSize == 0
        return 0
      end

      # append blocks
      # if the msg is longer than 4MB (to be safe, we use 4,000,000), we should break it into multiple blocks
      chunk_size = 4000000
      blocks_uncommitted = []
      blocks_committed = []
      while msg.to_s.length > 0 do
        chunk = msg.slice!(0, chunk_size)
        blocks_uncommitted << upload_block(uri, chunk)
      end
      @log.info "uncommitted blocks : #{blocks_uncommitted}"
      # commit blocks
      commit_blocks(uri, blocks_committed, blocks_uncommitted, file_path)
      return dataSize
    end # append_blob

    # upload one block to the blob
    # parameters:
    #   uri: URI. blob URI
    #   msg: string. block content
    # returns:
    #   string. block id
    def upload_block(uri, msg)
    begin
      base64_blockid = Base64.encode64(SecureRandom.uuid)
      request_id = SecureRandom.uuid
      append_uri = URI.parse("#{uri.to_s}&comp=block&blockid=#{base64_blockid}")

      put_block_req = create_blob_put_request(append_uri, msg, request_id, nil)
      http = OMS::Common.create_secure_http(append_uri, @proxy_config)
      OMS::Common.start_request(put_block_req, http)
    rescue => e
         @log.debug "Error in upload_block : #{e.message}"
         raise e
    end
      return base64_blockid
    end # upload_block

    # commit blocks of the blob.
    # NOTE: the order of the committed and uncommitted blocks determines the sequence of the file content
    # parameters:
    #   uri: URI. blob URI
    #   blocks_committed: string[]. committed block id list, which already exist
    #   blocks_uncommitted: string[]. uncommitted block id list, which are just uploaded
    #   file_path: string. file path
    def commit_blocks(uri, blocks_committed, blocks_uncommitted, file_path)
      doc = REXML::Document.new "<BlockList />"
      blocks_committed.each { |blockid| doc.root.add_element(REXML::Element.new("Committed").add_text(blockid)) }
      blocks_uncommitted.each { |blockid| doc.root.add_element(REXML::Element.new("Uncommitted").add_text(blockid)) }

      commit_msg = doc.to_s
      #@log.info "commit message : #{commit_msg}"

      blocklist_uri = URI.parse("#{uri.to_s}&comp=blocklist")
      request_id = SecureRandom.uuid
      put_blocklist_req = create_blob_put_request(blocklist_uri, commit_msg, request_id, file_path)
      http = OMS::Common.create_secure_http(blocklist_uri, @proxy_config)
      OMS::Common.start_request(put_blocklist_req, http)

      rescue => e
         @log.debug "Error in commit_blocks : #{e.message}"
         raise e.message
    end # commit_blocks

    # parse the tag to get the settings and append the message to blob
    # parameters:
    #   tag: string. the tag of the item
    #   records: string[]. an arrary of data
    def handle_records(tag, records)
      @log.trace "Handling record : #{tag}"
      @log.trace "Content location : #{@@ContentlocationUri}"
      @log.trace "Primary Content location : #{@PrimaryContentLocation}"
      @log.trace "Secondary Content location : #{@SecondaryContentLocation}"
      
      @log.trace "Primary Token = #{@@PrimaryContentLocationAccessToken}"
      @log.trace "secondry Token = #{@@SecondaryContentLocationAccessToken}"

      modifiedcollections = get_changed_files(records)
      changed_records = update_records_with_upload_url(records)

      @log.trace "Record = #{changed_records}"
      @log.trace "Collections = #{modifiedcollections}"

      begin
        upload_file_to_azure_storage(modifiedcollections)
      rescue Exception => e
        OMS::Log.error_once("Cannot upload file to azure storage. Error:'#{e}'")
        notify_failures_to_ods("Cannot upload file to azure storage", "")
      end

      handle_record_internal(tag, changed_records)

      @log.debug "Success sending file change tracking record to ODS"
      return true 
    end

    def get_changed_files(records)
      dataItems = {}
      modifiedcollections = {}
      if records.has_key?("DataItems")
        dataItems = records["DataItems"]
        dataItems.each {|item| 
          if item.has_key?("ConfigChangeType") and item["ConfigChangeType"] == "Files" and item.has_key?("Collections")
             item["Collections"].each {|collection|
                if !@@ContentlocationUri.nil? and !@@ContentlocationUri.empty? and !collection.empty?
                   key = collection["CollectionName"]
                   date = collection["DateModified"]
		   contentLength = collection["Contents"].to_i
		   fileSize = collection["Size"].to_i
		   if contentLength != "0" and contentLength >= fileSize
                      fileName = date + '-' + File.basename(key)
                      uri = @@ContentlocationUri + '/' + OMS::Common.get_hostname + '/' + OMS::Configuration.agent_id + '/' + fileName
                      if collection["FileContentBlobLink"] == " " or (@@LastContentLocationUri.eql?(@@ContentlocationUri) == false)
                         modifiedcollections[key] = uri
                      end
		   end
                end
             }
          @@LastContentLocationUri = @@ContentlocationUri
          else
             @log.trace "Record is NOT of ConfigChangeType = Files, skipping"
             return modifiedcollections
          end
        }
      end
      return modifiedcollections
    end

    def update_records_with_upload_url(records)
      dataItems = {}
      if records.has_key?("DataItems")
        dataItems = records["DataItems"]
        dataItems.each {|item| 
          if item.has_key?("ConfigChangeType") and item["ConfigChangeType"] == "Files" and item.has_key?("Collections")
             item["Collections"].each {|collection|
              contentLength = collection["Contents"].to_i
              fileSize = collection["Size"].to_i 
              if contentLength != "0" and contentLength >= fileSize and !@@ContentlocationUri.nil? and !@@ContentlocationUri.empty? and !collection.empty?
                   key = collection["CollectionName"]
                   date = collection["DateModified"]
                   fileName = date + '-' + File.basename(key)
                   uri = @@ContentlocationUri + '/' + OMS::Common.get_hostname + '/' + OMS::Configuration.agent_id + '/' + fileName + "?resourceid=" + @@ContentlocationUriResourceId
                   collection["FileContentBlobLink"] = uri
                end
             }
          @@LastContentLocationUri = @@ContentlocationUri
          end
        }
      end
      return records 
    end

    def upload_file_to_azure_storage(collections)
      if !@@ContentlocationUri.nil? and !@@ContentlocationUri.empty?
         @log.trace "Primary Token = #{@@PrimaryContentLocationAccessToken}"
         @log.trace "secondry Token = #{@@SecondaryContentLocationAccessToken}"

         if !@@PrimaryContentLocationAccessToken.nil? or !@@SecondaryContentLocationAccessToken.nil?
            collections.each{|filePath, blob_uri| upload_file_to_blob(filePath, blob_uri, @@PrimaryContentLocationAccessToken, @@SecondaryContentLocationAccessToken)}
         end
      end
    end  

    def notify_failures_to_ods(message, filePath)
      headers = {}
        dataitem = {}
        dataitem["Timestamp"] = OMS::Common.format_time(Time.now.utc)
        dataitem["OperationStatus"] = message 
        dataitem["Computer"] = OMS::Common.get_hostname or "Unknown host"
        dataitem["Detail"] = filePath
        dataitem["Category"] = "Files"        
        dataitem["Solution"] = "ConfigurationChange"
        dataitem["CorrelationId"] = SecureRandom.uuid
        dataitem["ErrorId"] = "Error"
       records = {
         "DataType"=>"OPERATION_BLOB",
         "IPName"=>"LogManagement",
         "DataItems"=>[dataitem]
        }
       handle_record_internal("CONFIG_CHANGE_BLOB.CHANGETRACKING", records)
       @log.trace "Success Sending notification to ODS : #{dataitem["Detail"]}"
    end # post_data

    def handle_record_internal(key, record)
      @log.trace "Handling record : #{key}"
      extra_headers = {
        OMS::CaseSensitiveString.new('x-ms-client-request-retry-count') => "#{@num_errors}"
      }
      req = OMS::Common.create_ods_request(OMS::Configuration.ods_endpoint.path, record, @compress, extra_headers)
      unless req.nil?
        http = OMS::Common.create_ods_http(OMS::Configuration.ods_endpoint, @proxy_config)
        start = Time.now
          
        # This method will raise on failure alerting the engine to retry sending this data
        OMS::Common.start_request(req, http)
          
        ends = Time.now
        time = ends - start
        count = record.has_key?('DataItems') ? record['DataItems'].size : 1
        @log.debug "Success sending #{key} x #{count} in #{time.round(2)}s"
        OMS::Telemetry.push_qos_event(OMS::SEND_BATCH, "true", "", key, record, count, time)
        return true
      end
    rescue OMS::RetryRequestException => e
      @log.info "Encountered retryable exception. Will retry sending data later."
      @log.debug "Error:'#{e}'"
      # Re-raise the exception to inform the fluentd engine we want to retry sending this chunk of data later.
      raise e.message
    rescue => e
      # We encountered something unexpected. We drop the data because
      # if bad data caused the exception, the engine will continuously
      # try and fail to resend it. (Infinite failure loop)
      OMS::Log.error_once("Unexpecting exception, dropping data. Error:'#{e}'")
    end

    def upload_file_to_blob(filePath, blob_uri, primarytoken, secondrytoken)
      records = []
      isPrimaryTokenInUse = false
      if File.size(filePath) > 999999999
         notify_failures_to_ods("File size is greater than 100 MB.", filePath)
         return
      end
      begin
        records = IO.readlines(filePath)
      rescue IOError => e
         #error
         @log.debug "Error reading the file #{filePath}"
         notify_failures_to_ods("Error reading the file", filePath)
         return
      end

      if !primarytoken.nil?
         blobUriWithToken = blob_uri + '?' + primarytoken 
         isPrimaryTokenInUse = true
      else
         isPrimaryTokenInUse = false
         blobUriWithToken = blob_uri + '?' + secondrytoken
      end

      @log.debug "Blob URI to upload : #{blobUriWithToken}"
      begin
        start = Time.now
        dataSize = append_blob(blobUriWithToken, records, filePath)
        time = Time.now - start
        @log.debug "Success uploading blob uri"
        return
      rescue Exception => e
        @log.info  "Exception occured, retrying with secondry key. Error:'#{e}'"
        OMS::Log.error_once ("Exception occured, retrying with secondary key. Error:'#{e}'")
      end 

      if isPrimaryTokenInUse
      # try with secondry token
        begin
          @log.debug "Retrying sending data to BLOB using secondry token"
          blobUriWithToken = blob_uri + '?' + secondrytoken
          start = Time.now
          dataSize = append_blob(blobUriWithToken, records, filePath)
          time = Time.now - start
          @log.debug "Success sending #{dataSize} bytes of data to BLOB using secondry token #{time.round(3)}s"        
          return
        rescue Exception => e
           @log.info "Unexpecting exception, dropping data. Error:'#{e}'"
           OMS::Log.error_once("Unexpecting exception, dropping data")
        end
      end

      notify_failures_to_ods("Error Uploading the file", blob_uri)
      @log.info "Unexpecting exception, dropping data. Error:'#{e}'"
      OMS::Log.error_once("Unexpecting exception, dropping data")
    end

    def save_content_location()
      if !@buffer_path.empty?
         contentlocationfilepath = File.dirname(@buffer_path) + '/' + @@ContentLocationCacheFileName
         if File.exists?(contentlocationfilepath)
            File.open(contentlocationfilepath, "w") do |f|
                f.puts "#{@@ContentlocationUri}"
            end
         else
            File.write(contentlocationfilepath, "#{@@ContentlocationUri}")
         end
      end
      @log.debug "LastContentLocationUri written to : #{contentlocationfilepath}"
    end

    def format(tag, time, record)
      if record != {}
        @log.trace "Buffering #{tag}"
        return [tag, record].to_msgpack
      else
        return ""
      end
    end


    # NOTE! This method is called by internal thread, not Fluentd's main thread. So IO wait doesn't affect other plugins.
    def write(chunk)
      # Quick exit if we are missing something
      if !OMS::Configuration.load_configuration(omsadmin_conf_path, cert_path, key_path)
        raise 'Missing configuration. Make sure to onboard. Will continue to buffer data.'
      end

      # Group records based on their datatype because OMS does not support a single request with multiple datatypes. 
      datatypes = {}
      unmergable_records = []
      chunk.msgpack_each {|(tag, record)|
        if record.has_key?('DataType') and record.has_key?('IPName')
          key = "#{record['DataType']}.#{record['IPName']}".upcase

          if datatypes.has_key?(key)
            # Merge instances of the same datatype and ipname together
            datatypes[key]['DataItems'].concat(record['DataItems'])
          else
            if record.has_key?('DataItems')
              datatypes[key] = record
            else
              unmergable_records << [key, record]
            end
          end
        else
          @log.warn "Missing DataType or IPName field in record from tag '#{tag}'"
        end
      }

      datatypes.each do |tag, records|
        handle_records(tag, records)
      end

      @log.trace "Handling #{unmergable_records.size} unmergeable records"
      unmergable_records.each { |key, record|
        handle_record(key, record)
      }

      save_content_location()
  end # Class



  private

    class ChunkErrorHandler
      include Configurable
      include PluginId
      include PluginLoggerMixin

      SecondaryName = "__ChunkErrorHandler__"

      Plugin.register_output(SecondaryName, self)

      def initialize
        @router = nil
      end

      def secondary_init(primary)
        @error_handlers = create_error_handlers @router
      end

      def start
        # NOP
      end

      def shutdown
        # NOP
      end

      def router=(r)
        @router = r
      end

      def write(chunk)
        chunk.msgpack_each {|(tag, record)|
          @error_handlers[tag].emit(record)
        }
      end
   
    private

      def create_error_handlers(router)
        nop_handler = NopErrorHandler.new
        Hash.new() { |hash, tag|
          etag = OMS::Common.create_error_tag tag
          hash[tag] = router.match?(etag) ?
                      ErrorHandler.new(router, etag) :
                      nop_handler
        }
      end

      class ErrorHandler
        def initialize(router, etag)
          @router = router
          @etag = etag
        end

        def emit(record)
          @router.emit(@etag, Fluent::Engine.now, record)
        end
      end

      class NopErrorHandler
        def emit(record)
          # NOP
        end
      end

   end #class ChunkErrorHandler

 end #class UploadFileContent

end # Module

