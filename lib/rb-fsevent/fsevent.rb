class FSEvent
  class EventFlags
    MustScanSubDirs = 0x00000001
    UserDropped = 0x00000002
    KernelDropped = 0x00000004
    EventIdsWrapped = 0x00000008
    HistoryDone = 0x00000010
    RootChanged = 0x00000020
    Mount = 0x00000040
    Unmount = 0x00000080
    ItemCreated = 0x00000100
    ItemRemoved = 0x00000200
    ItemInodeMetaMod = 0x00000400
    ItemRenamed = 0x00000800
    ItemModified = 0x00001000
    ItemFinderInfoMod = 0x00002000
    ItemChangeOwner = 0x00004000
    ItemXattrMod = 0x00008000
    ItemIsFile = 0x00010000
    ItemIsDir = 0x00020000
    ItemIsSymlink = 0x00040000

    attr_reader :flags

    def initialize(flags)
      @flags = flags.to_i
    end

    def to_a
      flags = []
      self.class.constants.each do |name|
        flags << name if @flags & self.class.const_get(name) > 0
      end
      flags
    end

    self.constants.each do |name|
      class_eval <<-END
        def #{name.to_s.split(/([A-Z][^A-Z]*)/).select{|a| !a.empty?}.join("_").downcase}?
          !! @flags & #{name} > 0
        end
      END
    end
  end

  class << self
    class_eval <<-END
      def root_path
        "#{File.expand_path(File.join(File.dirname(__FILE__), '..', '..'))}"
      end
    END
    class_eval <<-END
      def watcher_path
        "#{File.join(FSEvent.root_path, 'bin', 'fsevent_watch')}"
      end
    END
  end

  attr_reader :paths, :callback

  def watch(watch_paths, options=nil, &block)
    @paths      = Array(watch_paths)
    @callback   = block

    @use_flags_and_id = Hash === options && options.delete(:use_flags_and_id)

    if options.kind_of?(Hash)
      @options  = parse_options(options)
    elsif options.kind_of?(Array)
      @options  = options
    else
      @options  = []
    end
  end

  def run
    @running = true
    modified_paths = []
    while @running && !pipe.eof?
      if line = pipe.readline.chomp
        if line.empty?
          callback.call(modified_paths)
          modified_paths.clear
        else
          flags, id, path = line.split(":", 3)
          modified_paths << if @use_flags_and_id
            {:flags => EventFlags.new(flags), :id => id.to_i, :path => path}
          else
            path
          end
        end
      end
    end
  rescue Interrupt, IOError
  ensure
    stop
  end

  def stop
    if pipe
      Process.kill("KILL", pipe.pid)
      pipe.close
    end
  rescue IOError
  ensure
    @pipe = @running = nil
  end

  if RUBY_VERSION < '1.9'
    def pipe
      @pipe ||= IO.popen("#{self.class.watcher_path} #{options_string} #{shellescaped_paths}")
    end

    private

    def options_string
      @options.join(' ')
    end

    def shellescaped_paths
      @paths.map {|path| shellescape(path)}.join(' ')
    end

    # for Ruby 1.8.6  support
    def shellescape(str)
      # An empty argument will be skipped, so return empty quotes.
      return "''" if str.empty?

      str = str.dup

      # Process as a single byte sequence because not all shell
      # implementations are multibyte aware.
      str.gsub!(/([^A-Za-z0-9_\-.,:\/@\n])/n, "\\\\\\1")

      # A LF cannot be escaped with a backslash because a backslash + LF
      # combo is regarded as line continuation and simply ignored.
      str.gsub!(/\n/, "'\n'")

      return str
    end
  else
    def pipe
      @pipe ||= IO.popen([self.class.watcher_path] + @options + @paths)
    end
  end

  private

  def parse_options(options={})
    opts = []
    opts.concat(['--since-when', options[:since_when]]) if options[:since_when]
    opts.concat(['--latency', options[:latency]]) if options[:latency]
    opts.push('--no-defer') if options[:no_defer]
    opts.push('--watch-root') if options[:watch_root]
    opts.push('--file') if options[:file]
    # ruby 1.9's IO.popen(array-of-stuff) syntax requires all items to be strings
    opts.map {|opt| "#{opt}"}
  end

end
