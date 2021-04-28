require 'yajl'
require 'yajl/json_gem'
require 'securerandom' # SecureRandom.uuid 

require_relative 'oms_common'

module OMS
    class AuditdPlugin

        def initialize(log)
            @log = log
        end

        def transform_and_wrap(event, hostname, time)
            if event.nil?
                @log.error "Transformation of Auditd Plugin input failed; Empty input"
                return nil
            end

            if !event.has_key?("records") or event["records"].nil?
                @log.error "Transformation of Auditd Plugin input failed; Missing field 'records'"
                return nil
            end

            if !event["records"].is_a?(Array) or event["records"].size == 0
                @log.error "Transformation of Auditd Plugin input failed; Invalid 'records' value"
                return nil
            end

            if !event.has_key?("Timestamp") or event["Timestamp"].nil?
                @log.error "Transformation of Auditd Plugin input failed; Missing field 'Timestamp'"
                return nil
            end

            if !event.has_key?("SerialNumber") or event["SerialNumber"].nil?
                @log.error "Transformation of Auditd Plugin input failed; Missing field 'SerialNumber'"
                return nil
            end

            records = []

            event["records"].each do |record|
                if !record.is_a?(Hash) || record.empty?
                    @log.error "Transformation of Auditd Plugin input failed; Invalid data in data record"
                    return nil
                end
                record["Timestamp"] = OMS::Common.format_time(event["Timestamp"].to_f)
                record["AuditID"] = event["Timestamp"] + ":" + event["SerialNumber"].to_s
                record["SerialNumber"] = event["SerialNumber"]
                record["Computer"] = hostname
                if event.has_key?("ProcessFlags")
                    record["ProcessFlags"] = event["ProcessFlags"]
                end
                records.push(record)
            end

            wrapper = {
                "DataType"=>"LINUX_AUDITD_BLOB",
                "IPName"=>"Security",
                "DataItems"=>records
            }

            return wrapper
        end

    end # class

    class AuditdDSCLog

        def initialize(log)
            @log = log
        end

        def transform(record, hostname, time)
            operation_name = "#failed#"
            operation_result = ""
            dsc_version = ""
            has_auditd = false
            auditd_pid = 0
            auomscollect_pid = 0
            auoms_pid = 0
            status_regex = /^STATUS:(?<operation_name>(Test_Start|Test_End|Set_Start|Set_End)):<(?<operation_result>[^>]*)>:(?<version>[^:]*):(?<has_auditd>(true|false)):(?<auditd_pid>[0-9]+):(?<auomscollect_pid>[0-9]+):(?<auoms_pid>[0-9]+)/
            status_regex.match(record["message"]) { |match|
                operation_name = match["operation_name"]
                operation_result = match["operation_result"]
                dsc_version = match["version"]
                if match["has_auditd"] == "true"
                    has_auditd = true
                end
                auditd_pid = match["auditd_pid"].to_i
                auomscollect_pid = match["auomscollect_pid"].to_i
                auoms_pid = match["auoms_pid"].to_i
            }
            if operation_name == "#failed#"
                @log.error "Failed to parse STATUS message in DSC Log"
                return {}
            end
            dataitem = {}
            dataitem["Timestamp"] = OMS::Common.format_time(time)
            dataitem["Computer"] = hostname
            dataitem["RecordType"] = "AUOMS_METRIC"
            dataitem["RecordTypeCode"] = 10006
            dataitem["Namespace"] = "DSC"
            dataitem["Name"] = operation_name
            dataitem["version"] = dsc_version
            dataitem["Message"] = operation_result
            dataitem["Data"] = {
                "has_auditd"=>has_auditd,
                "auditd_pid"=>auditd_pid,
                "auomscollect_pid"=>auomscollect_pid,
                "auoms_pid"=>auoms_pid
            }.to_json

            @log.info "nxOMSAuditdPlugin STATUS: " + dataitem.to_s

            return dataitem
        end

        def transform_and_wrap(record, hostname, time)
            if record.is_a?(Hash) && !record.empty? && record.has_key?("message") && record["message"].start_with?("STATUS:")
                dataitem = transform(record, hostname, time)
                if !dataitem.empty?
                    wrapper = {
                        "DataType"=>"LINUX_AUDITD_BLOB",
                        "IPName"=>"Security",
                        "DataItems"=>[dataitem]
                    }
                    return wrapper
                end
            end
            return {}
        end

    end # class
end # module
