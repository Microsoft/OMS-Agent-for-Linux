module Fluent
  class FortigateSecurityEvents < Filter

    Fluent::Plugin.register_filter('filter_fortigate_security', self)

    def initialize
      super
      require_relative 'omslog'
      require_relative 'oms_common'
      require_relative 'fortigate_lib'
    end

    # Interval in seconds to refresh the cache
    config_param :ip_cache_refresh_interval, :integer, :default => 300

    def configure(conf)
      super
      @ip_cache = OMS::IPcache.new @ip_cache_refresh_interval
    end

    def start
      super
    end

    def shutdown
      super
    end

    def filter(tag, time, record)

      # Use Time.now, because it is the only way to get subsecond precision in version 0.12.
      # The time may be slightly in the future from the ingestion time.
      record['Timestamp'] = OMS::Common.format_time(Time.now.to_f)
      record['EventTime'] = OMS::Common.format_time(time)
      record.delete 'time'

      hostname = record['host']
      record['Host'] = hostname
      record.delete 'host'

      host_ip = @ip_cache.get_ip(hostname)
      if host_ip.nil?
        OMS::Log.warn_once("Failed to get the IP for #{hostname}.")
      else
        record['HostIP'] = host_ip
      end

      # The tag should looks like this : oms.security.local4.warn
      tags = tag.split('.')
      record['Facility'] = tags[tags.size - 2]
      record['Severity'] = tags[tags.size - 1]

      fortigate = Fortinet::Fortigate.new(@log)
      record = fortigate.parse(record)

      wrapper = {
        'DataType' => 'SECURITY_CEF_BLOB',
        'IPName' => 'Security',
        'DataItems' => [record]
      }

      wrapper
    end
  end
end
