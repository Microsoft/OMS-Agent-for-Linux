require 'fluent/input'
require 'fluent/config/error'
require 'yaml/store'
require 'fileutils'

module Fluent
  class DscMonitoringInput < Input
    Fluent::Plugin.register_input('dsc_monitor', self)

    config_param :tag, :string, :default=>nil
    config_param :check_install_interval, :time, :default=>86400
    config_param :check_status_interval, :time, :default=>1800
    config_param :dsc_cache_file, :string, :default=>'/var/opt/microsoft/omsagent/state/dsc_cache.yml'
   
    def configure(conf)
      super
      if !@tag 
        raise Fluent::ConfigError, "'tag' option is required on dsc_checks input"
      end
    end

    def start
      super
      @finished_check_install = false
      @finished_check_status = false
      @thread_check_install = Thread.new(&method(:run_check_install))
      @thread_check_status = Thread.new(&method(:run_check_status))
      if !File.exists?(dsc_cache_file)
        File.new(dsc_cache_file, "w", 0644)
      else
        File.chmod(0644, dsc_cache_file)
      end
      @dsc_cache = YAML::Store.new(dsc_cache_file) # The existing file will be read.
    end

    def check_install
      dpkg = (%x(which dpkg > /dev/null 2>&1; echo $?)).to_i
      if dpkg == 0
        %x(dpkg --list omsconfig > /dev/null 2>&1; echo $?).to_i
      else
        %x(rpm -qi omsconfig > /dev/null 2>&1; echo $?).to_i
      end
    end

    def run_check_install
      until @finished_check_install
        @install_status = check_install

        if @install_status == 1
           router.emit(@tag, Time.now.to_f, {"message"=>"omsconfig is not installed, OMS Portal \
configuration will not be applied and solutions such as Change Tracking and Update Assessment will \
not function properly. omsconfig can be installed by rerunning the omsagent installation"})
        end
        sleep @check_install_interval
      end
    end

    def get_dsc_status
      begin
        python = %x(which python2)
        if !python.empty?
            dsc_status = %x(/opt/microsoft/omsconfig/Scripts/TestDscConfiguration.py)
        else # assume python3, since /some/ python is an install prereq and we have a rescue below regardless
            dsc_status = %x(/opt/microsoft/omsconfig/Scripts/python3/TestDscConfiguration.py)
        end
      rescue => error
        OMS::Log.error_once("Unable to run TestDscConfiguration.py for dsc : #{error}")
        return 1
      end
      if dsc_status.match('"InDesiredState": true')
        return 0
      else
        return 1
      end
    end

    def run_check_status
      begin
      sleep @check_status_interval
    
      until @finished_check_status && @install_status == 0
        dsc_status = get_dsc_status

        # returns value of dsc configuration test from the cache
        # if key does not exist, assigns the string as value
        stored_dsc_status = @dsc_cache.transaction {
          @dsc_cache.fetch(:status, "DSC configuration test status not stored yet")
        }

        if dsc_status == 1 and stored_dsc_status == 1
          router.emit(@tag, Time.now.to_f, {"message"=>"Two successive configuration applications from \
OMS Settings failed – please report issue to github.com/Microsoft/PowerShell-DSC-for-Linux/issues"})
        end

        # store dsc configuration test status in the cache
        @dsc_cache.transaction { 
          @dsc_cache[:status] = dsc_status
          @dsc_cache.commit
        }
        sleep @check_status_interval
      end 
      rescue => e
        $log.error "DSC check status failed. Error: #{e}"
      end
    end       

    def shutdown
      super
      @finished_check_install = true
      @finished_check_status = true
      @thread_check_install.exit
      @thread_check_status.exit
      @thread_check_install.join
      @thread_check_status.join
    end

  end
end
