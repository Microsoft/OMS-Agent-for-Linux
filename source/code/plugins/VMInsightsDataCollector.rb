# frozen_string_literal: true

require 'scanf'

module VMInsights
    require_relative 'VMInsightsIDataCollector.rb'

    class DataCollector < IDataCollector
        def initialize(log, root_directory_name="/")
            @log = log
            @root = root_directory_name
            @baseline_exception = RuntimeError.new "baseline has not been called"
            @cpu_count = nil
            @saved_net_data = nil
            @saved_disk_data = DiskInventory.new(@log, @root)
        end

        def baseline
            @baseline_exception = nil
            @cpu_count, is_64_bit = get_cpu_info_baseline
            DataWithWrappingCounter.set_32_bit(! is_64_bit)
            @saved_net_data = get_net_data
            @saved_disk_data.baseline
            u, i = get_cpu_idle
            { :up => u, :idle => i }
        end

        def start_sample
        end

        def end_sample
        end

        def get_available_memory_kb
            available = nil
            total = nil
            File.open(File.join(@root, "proc", "meminfo"), "rb") { |f|
                begin
                    line = f.gets
                    next if line.nil?
                    line.scanf("%s%d%s") { |label, value, uom|
                        if (label == "MemTotal:" && value >= 0 && uom == "kB")
                            total = value
                        elsif (label == "MemAvailable:" && value >= 0 && uom == "kB")
                            available = value
                        end
                    }
                end until f.eof?
            }

            raise IDataCollector::Unavailable, "Available memory not found" if available.nil?
            raise IDataCollector::Unavailable, "Total memory not found" if total.nil?

            return available, total
        end

        # returns: cummulative uptime, cummulative idle time
        def get_cpu_idle
            uptime = nil
            idle = nil
            File.open(File.join(@root, "proc", "uptime"), "rb") { |f|
                line = f.gets
                next if line.nil?
                line.scanf(" %f %f ") { |u, i|
                    uptime = u
                    idle = i
                }
            }

            raise IDataCollector::Unavailable, "Uptime not found" if uptime.nil?
            raise IDataCollector::Unavailable, "Idle time not found" if idle.nil?

            return uptime, idle
        end

        # returns:
        #   number of CPUs available for scheduling tasks
        # raises:
        #   Unavailable if not available
        def get_number_of_cpus
            raise @baseline_exception if @baseline_exception
            raise @cpu_count if @cpu_count.kind_of? StandardError
            @cpu_count
        end

        # return:
        #   An array of objects with methods:
        #       mount_point
        #       size_in_bytes
        #       free_space_in_bytes
        #       device_name
        def get_filesystems
            result = []
            df = File.join(@root, "bin", "df")
            IO.popen([df, "--block-size=1", "-T"], { :in => :close, :err => File::NULL }) { |io|
                while (line = io.gets)
                    a = line.split(" ")
                    if (a[1] =~ /^(ext[234]|xfs)$/)
                        begin
                            result << Fs.new(a[0], a[6], a[2], a[4]) if a.size == 7
                        rescue ArgumentError => ex
                            # malformed input
                            @log.debug() { "#{__method__}: #{ex}: '#{line}'" }
                        end
                    end
                end
            }
            result
        rescue => ex
            raise IDataCollector::Unavailable.new ex.message
        end

        # returns:
        #   An array of objects with methods:
        #       device
        #       bytes_received  since last call or baseline
        #       bytes_sent      since last call or baseline
        #   Note: Only devices that are "UP" or had activity are included
        def get_net_stats
            raise @baseline_exception if @baseline_exception
            result = []
            new_data = get_net_data
            new_data.each_pair { |key, new_value|
                previous_value = @saved_net_data[key]
                if previous_value.nil?
                    result << new_value if new_value.up
                else
                    diff = new_value - previous_value
                    result << diff if (new_value.up || diff.active?)
                end
            }
            @saved_net_data = new_data
            result
        end

        def get_disk_stats(dev)
            raise @baseline_exception if @baseline_exception
            @saved_disk_data.get_disk_stats(dev)
        end

    private

        class DataWithWrappingCounter
            @@counter_modulus = 0   # default to cause exception

            def self.set_32_bit(is32bit)
                @@counter_modulus = (2 ** (is32bit ? 32 : 64))
            end

        protected

            def sub_with_wrap(a, b)
                (@@counter_modulus + a - b) % @@counter_modulus
            end

        end

        class DiskInventory
            def initialize(log, root)
                @log = log
                @root = root
                @sector_sizes = Hash.new { |h, k| h[k] = get_sector_size(k) }
                @saved_disk_data = { }
            end

            def baseline
                @sector_sizes.clear()
                @sector_sizes.merge!(get_sector_sizes)
                @saved_disk_data = { }
                @sector_sizes.each_pair { |d, s|
                    begin
                        @saved_disk_data[d] = get_disk_data(d, s)
                    rescue IDataCollector::Unavailable => ex
                        # NOP
                    end
                }
            end

            def get_disk_stats(dev)
                current = get_disk_data dev, @sector_sizes[dev]
                raise IDataCollector::Unavailable, "no data for #{dev}" if current.nil?
                previous = @saved_disk_data[dev]
                @saved_disk_data[dev] = current
                raise IDataCollector::Unavailable, "no previous data for #{dev}" if previous.nil?
                current - previous
            end

        private

            def get_sector_size(dev)
                raise ArgumentError, "dev is nil" if dev.nil?
                data = get_sector_sizes
                data[dev]
            end

            def get_sector_sizes()
                cmd = [ File.join(@root, "bin", "lsblk"), "-sd", "-oNAME,LOG-SEC" ]
                result = { }
                begin
                    IO.popen(cmd, { :in => :close }) { |io|
                        io.gets # skips the header
                        while (line = io.gets)
                            s = line.split(" ")
                            next if s.length < 2
                            result[s[0]] = s[1].to_i
                        end
                    }
                rescue => ex
                    @log.debug() { "#{__method__}: #{ex}" }
                end
                result
            end

            def get_disk_data(dev, sector_size)
                path = File.join(@root, "sys", "class", "block", dev, "stat")
                begin
                    File.open(path, "rb") { |f|
                        line = f.gets
                        raise Unavailable, "#{path}: is empty" if line.nil?
                        data = line.split(" ")
                        RawDiskData.new(
                                        dev,
                                        Time.now,
                                        data[0].to_i,
                                        data[2].to_i,
                                        data[4].to_i,
                                        data[6].to_i,
                                        sector_size
                                        )
                    }
                rescue Errno::ENOENT => ex
                    raise IDataCollector::Unavailable, "#{path}: #{ex}"
                end
            end

            class DiskData
                def initialize(d, t, r, rb, w, wb)
                    @device = -d
                    @delta_time = t
                    @reads = r
                    @bytes_read = rb
                    @writes = w
                    @bytes_written = wb
                end

                attr_reader :device, :reads, :bytes_read, :writes, :bytes_written, :delta_time
            end

            class RawDiskData < DataWithWrappingCounter
                def initialize(d, t, r, rs, w, ws, ss)
                    @device = -d
                    @time = t
                    @reads = r
                    @read_sectors = rs
                    @writes = w
                    @write_sectors = ws
                    @sector_size = ss
                end

                attr_reader :device, :time, :reads, :read_sectors, :writes, :write_sectors

                def -(other)
                    raise ArgumentError, "#{device} != #{other.device}" unless device == other.device
                    delta_t = (time - other.time)
                    DiskData.new(
                                    device,
                                    delta_t,
                                    sub_with_wrap(reads, other.reads),
                                    @sector_size.nil? ? nil : (sub_with_wrap(read_sectors, other.read_sectors) * @sector_size),
                                    sub_with_wrap(writes, other.writes),
                                    @sector_size.nil? ? nil : (sub_with_wrap(write_sectors, other.write_sectors) * @sector_size)
                                )
                end

            end

        end

        class NetData
            def initialize(d, t, r, s)
                @device = -d
                @delta_time = t
                @bytes_received = r
                @bytes_sent = s
            end

            def active?
                (@bytes_received > 0) || (@bytes_sent > 0)
            end

            attr_reader :device, :delta_time, :bytes_received, :bytes_sent

        end

        class RawNetData < DataWithWrappingCounter
            def initialize(d, t, u, r, s)
                @time = t
                @device = -d
                @bytes_received = r
                @bytes_sent = s
                @up = u
            end

            attr_reader :up

            def -(other)
                NetData.new @device,
                            @time - other.time,
                            sub_with_wrap(@bytes_received, other.bytes_received),
                            sub_with_wrap(@bytes_sent, other.bytes_sent)
            end

            attr_reader :device, :time, :bytes_received, :bytes_sent
        end

        def get_net_data
            sys_devices_virtual_net = File.join(@root, "sys", "devices", "virtual", "net")
            devices_up = get_up_net_devices
            result = { }
            File.open(File.join(@root, "proc", "net", "dev"), "rb") { |f|
                now = Time.now
                while (line = f.gets)
                    line = line.split(" ")
                    next if line.empty?
                    dev = line[0]
                    next unless (dev.end_with? ":")
                    dev.chop!
                    next if Dir.exist? File.join(sys_devices_virtual_net, dev)
                    result[dev] = RawNetData.new(dev, now, devices_up[dev], line[1].to_i, line[9].to_i)
                end
            }
            result
        end

        def get_up_net_devices
            result = Hash.new(false)
            begin
                File.open(File.join(@root, "proc", "net", "route")) { |f|
                    f.gets # skip the header
                    while (line = f.gets)
                        dev = line.partition(/\t+/)[0]
                        result[dev] = true unless dev.empty?
                    end
                }
            rescue => ex
                @log.debug() { "#{__method__}: #{ex}" }
            end
            result
        end

        class Fs
            def initialize(device_name, mount_point, size_in_bytes, free_space_in_bytes)
                raise ArgumentError, mount_point unless mount_point.start_with? "/"
                raise ArgumentError, device_name unless device_name.start_with?("/dev/")
                device_name = device_name.sub(/^\/dev\//, '')
                @device_name = device_name
                @mount_point = mount_point
                @size_in_bytes = Integer(size_in_bytes, 10)
                raise ArgumentError, size_in_bytes if (@size_in_bytes == 0)
                @free_space_in_bytes = Integer(free_space_in_bytes, 10)
            end

            def <=>(o)
                r = device_name <=> o.device_name
                return r unless r.zero?
                r = mount_point <=> o.mount_point
                return r unless r.zero?
                r = size_in_bytes <=> o.size_in_bytes
                return r unless r.zero?
                free_space_in_bytes <=> o.free_space_in_bytes
            end

            attr_reader :device_name, :mount_point, :size_in_bytes, :free_space_in_bytes
            alias_method :to_s, :inspect
        end

        def get_cpu_info_baseline
            lscpu = File.join(@root, "usr", "bin", "lscpu")

            count = 0
            IO.popen([lscpu, "-p" ], { :in => :close, :err => File::NULL }) { |io|
                while (line = io.gets)
                    count += 1 if ('0' .. '9').member?(line[0])
                end
            }
            count = Unavailable.new "No CPUs found" if count.zero?

            is_64_bit = false
            IO.popen({"LC_ALL" => "C"}, lscpu, { :in => :close, :err => File::NULL }) { |io|
                while (line = io.gets)
                    if line.start_with? "CPU op-mode(s):"
                        is_64_bit = (line.include? "64-bit")
                        break
                    end
                end
            }

            return count, is_64_bit
        rescue => ex
            return (Unavailable.new ex.message), true
        end

    end # DataCollector

end #module
