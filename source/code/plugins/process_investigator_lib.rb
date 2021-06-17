require_relative 'oms_common'
require 'securerandom'
require 'socket'

module OMS
    class ProcessInvestigator

        @@PIVersion = "1.20.0605.0001"

        # The limit for event hub messages is 256k, assuming utf16, that's 128k characters.
        # Leaving some room for overhead, truncate at 100k characters.
        @@MaxResultLength = 100000

        def initialize(log)
            @log = log
        end

        def create_basic_record()
            record = {}
            record["MachineName"] = (Common.get_hostname or "Unknown Host")
            record["OSName"] = "Linux " + (Common.get_os_full_name or "Unknown Distro")
            record["PIVersion"] = @@PIVersion
            record["PICorrelationId"] = SecureRandom.uuid

            return record
        end
        
        def get_basic_error_result(errorString, errorMessage)
            basicErrorResult = {"logs"=>[{"Level"=>"Error", "ErrorString" => errorString, "Message"=>errorMessage}], "ScanSummary"=>{"scanOutcome"=>"Failed"}}.to_json
            return basicErrorResult
        end

        def transform_and_wrap(results)
            processList = nil
            record = create_basic_record()
            record["PIEventType"] = "Telemetry"
            
            if results.is_a?(Hash)
                results = results["message"].to_s
            else
                results = results.to_s
            end
            if results.nil? or results.length == 0
                @log.error "Process Investigator Filter failed. Empty message."
                record["PiResults"] = get_basic_error_result("OutputEmpty", "Process Investigator Filter failed. Empty message.")
            else
                # Check for valid guid as session id
                if results[0..35] =~ /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/
                    record["SessionId"] = results[0..35]
                    results = (results[37..-1] or "")
                
                    (piResults_parsed = JSON.parse(results)) rescue nil
                    
                    if piResults_parsed.is_a?(Hash) 
                        if piResults_parsed["processList"].is_a?(Array) and piResults_parsed["processList"].length > 0
                            processList = piResults_parsed["processList"]
                            shortProcessList = []
                            for process in processList
                                if process.is_a?(Hash)
                                    shortProcessList.push({"classification"=>(process["classification"] or "Unknown"),"processName"=>(process["processName"] or "Unknown")})
                                else
                                    shortProcessList.push({"classification"=>"Unknown","processName"=>"Unknown"})
                                end
                            end
                            piResults_parsed["processList"] = shortProcessList
                        end
                        record["PiResults"] = piResults_parsed.to_json
                    else
                        record["PiResults"] = get_basic_error_result("InvalidOutput", results)
                    end
                    
                else
                    record["PiResults"] = get_basic_error_result("MissingSessionId", results)
                end
            end

            if record["PiResults"].length > @@MaxResultLength then
               record["PiResults"]=record["PiResults"][0..@@MaxResultLength-1] + " ... TRUNCATED DATA"
            end
        
            process_investigator_blob = {
                "DataType"=>"PROCESS_INVESTIGATOR_BLOB",
                "IPName"=>"Security",
                "DataItems"=>[record]
            }

            if !processList.nil?
                for process in processList
                    begin
                        process_record = create_basic_record()
                        process_record["SessionId"] = record["SessionId"]
                        if process.is_a?(Hash)
                            if process.to_json.length <= @@MaxResultLength then
                                process_record["PIEventType"] = "Telemetry"
                                process_record["PiResults"] = {"processInfo"=>process}.to_json
                                process_investigator_blob["DataItems"].push(process_record)
                                alert_record = process_record.clone
                                alert_record["PIEventType"] = "Alert"
                                alert_record["PiResults"] = process.to_json
                                process_investigator_blob["DataItems"].push(alert_record)
                                
                            else
                                process_record["PIEventType"] = "Telemetry"
                                process_record["PiResults"] = get_basic_error_result("ProcessInfoTruncated", process.to_json[0..@@MaxResultLength-1] + " ... TRUNCATED DATA")
                                process_investigator_blob["DataItems"].push(process_record)
                            end
                        else
                            process_record["PIEventType"] = "Telemetry"
                            process_record["PiResults"] = get_basic_error_result("ProcessInfoInvalid", process)
                            process_investigator_blob["DataItems"].push(process_record)
                        end
                    rescue Exception => e
                        error_record = create_basic_record()
                        error_record["PIEventType"] = "Telemetry"
                        error_record["SessionId"] = record["SessionId"]
                        error_record["PiResults"] = get_basic_error_result("AlertParsingError", e.message)
                        process_investigator_blob["DataItems"].push(error_record)
                   end
                end
            end

            @log.info "Processed PI output"
            @log.info process_investigator_blob

            return process_investigator_blob
        end # transform_and_wrap
    end # class
end # module

