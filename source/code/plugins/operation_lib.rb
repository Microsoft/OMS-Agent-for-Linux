# Copyright (c) Microsoft Corporation. All rights reserved.
module OperationModule
  class LoggingBase
    def log_error(text)
    end
  end
  
  class RuntimeError < LoggingBase
    def log_error(text)
      $log.info "RuntimeError: #{text}"
    end
  end
  
  class Operation
    require_relative 'oms_common'

    BUFFER_QUEUE_WARNING_THRESHOLD_PERCENTAGE = 90

    def initialize(error_handler)
      @error_handler = error_handler
    end
    
    def filter(record, time)
      if record.is_a?(Hash) && record['type'] == 'out_oms' && record['config'].is_a?(Hash) && record['config']['buffer_queue_limit'].is_a?(String) && record['buffer_queue_length'].is_a?(Integer)
        buffer_queue_limit = record['config']['buffer_queue_limit'].to_i
        buffer_queue_length = record['buffer_queue_length']
        if buffer_queue_limit != 0 && (buffer_queue_length * 100 / buffer_queue_limit) >= BUFFER_QUEUE_WARNING_THRESHOLD_PERCENTAGE
          computer = OMS::Common.get_hostname or "Unknown host"
          return {
            "Timestamp"=>OMS::Common.format_time(time),
            "OperationStatus"=>"Warning",
            "Computer"=>computer,
            "Detail"=>"OMS Agent for Linux buffer queue is 90% full - adjust agent configuration for higher throughput.",
            "Category"=>"OMS Agent for Linux buffer is 90% full",
            "Solution"=>"Log Management",
            "HelpLink"=>""
          }
        end
      end

      return {}
    end

    def filter_generic(record,time)
      if record.is_a?(Hash) && !record.empty? && record.has_key?("message")
        dataitem = {}
        dataitem["Timestamp"] = OMS::Common.format_time(time)
        dataitem["OperationStatus"] = "Warning"
        dataitem["Computer"] = OMS::Common.get_hostname or "Unknown host"
        dataitem["Detail"] = record["message"]
        dataitem["Category"] = "OMS Agent for Linux issue"
        dataitem["Solution"] = "Log Management"
        return dataitem
      end
      return {}
    end

    def filter_auditd_plugin(record,time)
      if record.is_a?(Hash) && !record.empty? && record.has_key?("message")
        dataitem = {}
        dataitem["Timestamp"] = OMS::Common.format_time(time)
        dataitem["OperationStatus"] = "Error"
        dataitem["Computer"] = OMS::Common.get_hostname or "Unknown host"
        dataitem["Detail"] = record["message"]
        dataitem["Category"] = "OMS Auditd Plugin issue"
        dataitem["Solution"] = "Security"
        return dataitem
      end
      return {}
    end
 
    def filter_and_wrap(tag, record, time)
      return {} unless tag.is_a?(String)
      tag_type = tag.match(/[^\.]*$/) 
      case tag_type[0]
      #when "buffer" # Legacy case commented out for now.
      #  data_item = filter(record, time)
      when "health"
        data_item = filter(record, time)
      when "dsc" 
        data_item = filter_generic(record, time)
      when "auditd_plugin"
        data_item = filter_auditd_plugin(record, time)
      end

      return {} if data_item.nil?
      return {} if data_item.length == 0
      return {
        "DataType"=>"OPERATION_BLOB",
        "IPName"=>"LogManagement",
        "DataItems"=>[data_item]
      }
    end

  end
end

