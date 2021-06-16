require 'fluent/input'
require 'fluent/config/error'

module Fluent

  class Heartbeat_Request < Input
    Plugin.register_input('heartbeat_request', self)

    def initialize
      super
      require_relative 'agent_maintenance_script'
      require_relative 'oms_configuration'
    end

    config_param :run_interval, :time, :default => '20m'
    config_param :omsadmin_conf_path, :string
    config_param :cert_path, :string
    config_param :key_path, :string
    config_param :pid_path, :string
    config_param :proxy_path, :string, :default => '/etc/opt/microsoft/omsagent/proxy.conf' #optional
    config_param :os_info, :string, :default => '/etc/opt/microsoft/scx/conf/scx-release' #optional
    config_param :install_info, :string, :default => '/etc/opt/microsoft/omsagent/sysconf/installinfo.txt' #optional

    MIN_QUERY_INTERVAL = 60
    MAX_QUERY_INTERVAL = 60 * 60 * 24 * 7

    def configure (conf)
      super
      if !@omsadmin_conf_path
        raise Fluent::ConfigError, "'omsadmin_conf_path' option is required on heartbeat_request input"
      end
      if !@cert_path
        raise Fluent::ConfigError, "'cert_path' option is required on heartbeat_request input"
      end
      if !@key_path
        raise Fluent::ConfigError, "'key_path' option is required on heartbeat_request input"
      end
      if !@pid_path
        raise Fluent::ConfigError, "'pid_path' option is required on heartbeat_request input"
      end
    end

    def start
      @maintenance_script = MaintenanceModule::Maintenance.new(@omsadmin_conf_path, @cert_path,
                              @key_path, @pid_path, @proxy_path, @os_info, @install_info, @log)

      if @run_interval
        @finished = false
        @condition = ConditionVariable.new
        @mutex = Mutex.new
        @thread = Thread.new(&method(:run_periodic))
      else
        enumerate
      end
    end

    def shutdown
      if @run_interval
        @mutex.synchronize {
          @finished = true
          @condition.signal
        }
        @thread.join
      end
    end

    # Any data produced by this is NOT sent to an output plugin or ODS
    def enumerate
      @maintenance_script.heartbeat
      if defined?(OMS::Configuration.topology_interval)
        query_interval = OMS::Configuration.topology_interval
        @run_interval = query_interval if !query_interval.nil? and query_interval.between?(MIN_QUERY_INTERVAL, MAX_QUERY_INTERVAL)
      end
      @maintenance_script.generate_dsc_metaconfig
    end

    def run_periodic
      @mutex.lock
      done = @finished
      until done
        @condition.wait(@mutex, @run_interval)
        done = @finished
        @mutex.unlock
        if !done
          enumerate
        end
        @mutex.lock
      end
      @mutex.unlock
    end

  end # class Heartbeat_Request

end # module Fluent
