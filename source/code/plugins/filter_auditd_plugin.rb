
require_relative 'auditd_plugin_lib'
require_relative 'oms_common'

module Fluent
  class AuditdPluginFilter < Filter

    Fluent::Plugin.register_filter('filter_auditd_plugin', self)

    def configure(conf)
        super
        # Do the usual configuration here
        @hostname = OMS::Common.get_hostname or "Unknown host"
    end

    def start
        super
        # This is the first method to be called when it starts running
        # Use it to allocate resources, etc.
    end

    def shutdown
        super
        # This method is called when Fluentd is shutting down.
        # Use it to free up resources, etc.
    end

    def filter(tag, time, record)
        auditd_plugin = OMS::AuditdPlugin.new(@log)
        audit_blob = auditd_plugin.transform_and_wrap(record, @hostname, time)

        return audit_blob
    end # filter
  end # class

  class AuditdDSCLogFilter < Filter

    Fluent::Plugin.register_filter('filter_auditd_dsc_log', self)

    def configure(conf)
        super
        # Do the usual configuration here
        @hostname = OMS::Common.get_hostname or "Unknown host"
    end

    def start
        super
        # This is the first method to be called when it starts running
        # Use it to allocate resources, etc.
    end

    def shutdown
        super
        # This method is called when Fluentd is shutting down.
        # Use it to free up resources, etc.
    end

    def filter(tag, time, record)
        auditd_dsc_log = OMS::AuditdDSCLog.new(@log)
        dsc_log_blob = auditd_dsc_log.transform_and_wrap(record, @hostname, time)

        if !dsc_log_blob.empty?
          return dsc_log_blob
        end
    end # filter
  end # class
end # module
