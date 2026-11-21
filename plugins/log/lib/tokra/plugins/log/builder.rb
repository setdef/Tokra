# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Builder and its defaults adapted from tauri-plugin-log src/lib.rs

require "ferro/time"

module Tokra
  module Plugins
    module Log
      # The target of every record the page logs, followed by
      # <tt>:<location></tt> when the page names one (lib.rs:37).
      WEBVIEW_TARGET = "webview"

      # The largest a log file grows before it rotates, in bytes (lib.rs:46).
      DEFAULT_MAX_FILE_SIZE = 40_000

      # What happens to a full log file unless the builder says otherwise
      # (lib.rs:47).
      DEFAULT_ROTATION_STRATEGY = RotationStrategy::KeepOne.new

      # The clock of the default format and of rotated file names
      # (lib.rs:48).
      DEFAULT_TIMEZONE_STRATEGY = TimezoneStrategy::UseUtc.new

      # The date in a rotated file's name, such as
      # <tt>2026-11-13_09-41-07</tt>: time's format description
      # (lib.rs:53-54).
      LOG_DATE_FORMAT = Ractor.make_shareable(
        Ferro::Time::FormatDescription.parse_borrowed(1, "[year]-[month]-[day]_[hour]-[minute]-[second]")
      )

      # Builds the log plugin.
      #
      # An app wants its log lines in a few places at once, each line
      # stamped with when and where it came from, and its files kept to a
      # size. The Builder holds those choices: the targets, the level, the
      # filters, the line format, the clock, and how files rotate. Each
      # method returns the builder, so calls chain, and #build makes the
      # plugin, whose setup makes the Logger and attaches it.
      #
      # With no changes, the logger writes every level to standard output
      # and to the app's log directory, as
      # <tt>[2026-11-13][09:41:07][my-app][INFO] message</tt> in UTC, and
      # starts a log file over at 40000 bytes.
      #
      # Mirrors Tauri's <tt>tauri_plugin_log::Builder</tt> (lib.rs:395-709).
      #
      # === Examples
      #
      #   # Tauri's defaults
      #   Tokra::Builder.default.plugin(Builder.new.build)
      #
      #   # The terminal and the page's console, info and above
      #   Builder.new
      #     .level(:info)
      #     .targets([
      #       Target.new(TargetKind::Stdout.new),
      #       Target.new(TargetKind::Webview.new),
      #     ])
      #     .build
      #
      #   # Local time, keeping the last five full files
      #   Builder.new
      #     .timezone_strategy(TimezoneStrategy::UseLocal.new)
      #     .rotation_strategy(RotationStrategy::KeepSome.new(5))
      #     .build
      class Builder
        # The date and time at the start of a line (lib.rs:407).
        TIMESTAMP = Ractor.make_shareable(
          Ferro::Time::FormatDescription.parse_borrowed(1, "[[[year]-[month]-[day]][[[hour]:[minute]:[second]]")
        )
        private_constant :TIMESTAMP

        # Tauri's default format: time, target, level, message
        # (lib.rs:408-421).
        DEFAULT_FORMAT = Ractor.shareable_proc do |message, record|
          "#{DEFAULT_TIMEZONE_STRATEGY.get_now.format(TIMESTAMP)}[#{record.target}][#{record.level.upcase}] #{message}"
        end
        private_constant :DEFAULT_FORMAT

        # Builder#clear_format's format: the message alone (lib.rs:468-473).
        MESSAGE_ONLY = Ractor.shareable_proc { |message, _record| message }
        private_constant :MESSAGE_ONLY

        # log's level filters, from Off up, as LevelFilter::from_str reads
        # them (log lib.rs:460, 665-676).
        LEVEL_FILTERS = %i[off error warn info debug trace].freeze
        private_constant :LEVEL_FILTERS

        # The largest file size Rust's u64 holds.
        U64_MAX = (2 ** 64) - 1
        private_constant :U64_MAX

        # Makes a builder with Tauri's defaults (lib.rs:404-431).
        def initialize
          @_targets = [Target.new(TargetKind::Stdout.new), Target.new(TargetKind::LogDir.new)]
          @_format = DEFAULT_FORMAT
          @_level = :trace
          @_filters = []
          @_rotation_strategy = DEFAULT_ROTATION_STRATEGY
          @_timezone_strategy = DEFAULT_TIMEZONE_STRATEGY
          @_max_file_size = DEFAULT_MAX_FILE_SIZE
          @_skip_logger = false
        end

        # Sets what happens to a full log file (lib.rs:438-441).
        #
        # === Example
        #
        #   builder.rotation_strategy(RotationStrategy::KeepAll.new)
        def rotation_strategy(rotation_strategy)
          @_rotation_strategy = rotation_strategy
          self
        end

        # Sets the clock for rotated file names, and replaces the format
        # with one that reads that clock: <tt>[date][time][LEVEL][target]
        # message</tt>, the level before the target (lib.rs:443-457). A
        # later #format replaces it in turn.
        #
        # === Example
        #
        #   builder.timezone_strategy(TimezoneStrategy::UseLocal.new)
        def timezone_strategy(timezone_strategy)
          @_timezone_strategy = timezone_strategy
          @_format = Ractor.shareable_proc do |message, record|
            "#{timezone_strategy.get_now.format(TIMESTAMP)}[#{record.level.upcase}][#{record.target}] #{message}"
          end
          self
        end

        # Sets the size in bytes past which a log file rotates. Sizes larger
        # than Rust's u64 are clamped to it (lib.rs:459-466).
        #
        # === Example
        #
        #   builder.max_file_size(1_000_000)
        def max_file_size(max_file_size)
          @_max_file_size = [max_file_size, U64_MAX].min
          self
        end

        # Writes each message as it is, with no time, target, or level
        # (lib.rs:468-473).
        #
        # === Example
        #
        #   builder.clear_format
        def clear_format
          @_format = MESSAGE_ONLY
          self
        end

        # Sets the format every line takes before any target's own
        # (lib.rs:475-481). The format receives the message and the Record
        # and returns the line; +nil+ leaves the message as it was.
        #
        # === Example
        #
        #   builder.format(Ractor.shareable_proc { |message, record| "#{record.level}: #{message}" })
        def format(formatter = nil, &block)
          @_format = formatter || block
          self
        end

        # Sets the lowest level that is logged: +:trace+ (the default),
        # +:debug+, +:info+, +:warn+, +:error+, or +:off+, in any case,
        # as a Symbol or String (lib.rs:483-486).
        #
        # Raises ArgumentError with log's message for any other name.
        #
        # === Example
        #
        #   builder.level(:info)
        def level(level_filter)
          name = level_filter.to_s
          found = LEVEL_FILTERS.find { |filter| filter.to_s.casecmp?(name) }
          raise ArgumentError, "attempted to convert a string that doesn't match an existing log level" unless found

          @_level = found
          self
        end

        # :call-seq:
        #   level_for(module_name, level) -> raises NotImplementedError
        #
        # Raises NotImplementedError.
        #
        # == Why This Is Not Implemented
        #
        # Tauri's <tt>level_for(module, level)</tt> sets a level for the
        # records of one Rust module, such as <tt>hyper::client</tt>. A Rust
        # record carries its module path as its target. A Ruby record
        # carries no module: its target is the +progname+ the caller passed,
        # or the app's name, so there is nothing reliable to match.
        #
        # == Alternatives
        #
        # Filter on the target the caller does pass, with Builder#filter or
        # Target#filter:
        #
        #   builder.filter(Ractor.shareable_proc { |metadata|
        #     metadata.target != "sql" || metadata.level == :error
        #   })
        #
        # See: https://github.com/tauri-apps/plugins-workspace/blob/d4613ff0029ea65f5c6895c3a6f8f5668dd1b55e/plugins/log/src/lib.rs#L488-L491
        def level_for(_module_name, _level)
          raise NotImplementedError,
            "level_for is not implemented. Tauri's level_for filters by Rust module path, which Ruby " \
              "records lack. Use Builder#filter or Target#filter on the record's target instead."
        end

        # Adds a filter every record has to pass before it is formatted
        # (lib.rs:493-499). The filter receives the record's Metadata and
        # returns whether the record goes on.
        #
        # === Example
        #
        #   builder.filter(Ractor.shareable_proc { |metadata| !metadata.target.start_with?("sql") })
        def filter(callable = nil, &block)
          @_filters << (callable || block)
          self
        end

        # Removes all targets. Useful to ignore the default targets and
        # reconfigure them (lib.rs:501-505).
        #
        # === Example
        #
        #   builder.clear_targets.target(Target.new(TargetKind::Stdout.new))
        def clear_targets
          @_targets = []
          self
        end

        # Adds a log target to the logger (lib.rs:507-517).
        #
        # === Example
        #
        #   builder.target(Target.new(TargetKind::Webview.new))
        def target(target)
          @_targets << target
          self
        end

        # Replaces the targets of the logger (lib.rs:535-549).
        #
        # === Example
        #
        #   builder.targets([
        #     Target.new(TargetKind::Webview.new),
        #     Target.new(TargetKind::LogDir.new(file_name: "webview"))
        #       .filter(Ractor.shareable_proc { |metadata| metadata.target.start_with?(WEBVIEW_TARGET) }),
        #     Target.new(TargetKind::LogDir.new(file_name: "ruby"))
        #       .filter(Ractor.shareable_proc { |metadata| !metadata.target.start_with?(WEBVIEW_TARGET) }),
        #   ])
        def targets(targets)
          @_targets = targets.to_a.dup
          self
        end

        # Skips the creation and global registration of a logger.
        #
        # If you wish to use your own logger, call #skip_logger so that the
        # plugin does not attempt to attach a second one: Log.attach_logger
        # takes one logger per process. In this configuration no logger is
        # created, the plugin's <tt>log</tt> command logs to whatever
        # Log.logger answers, and the builder's targets are ignored. If you
        # ever register the plugin more than once in a process, as tests
        # do, call this method so the second registration does not fail
        # (lib.rs:519-533).
        #
        # === Example
        #
        #   plugin, max_level, logger = Tokra::Plugins::Log::Builder.new.split(app.handle)
        #   Tokra::Plugins::Log.attach_logger(max_level, logger)
        #   Tokra::Plugins::Log::Builder.new.skip_logger.build
        def skip_logger
          @_skip_logger = true
          self
        end

        # Makes the plugin and the logger apart, without attaching the
        # logger, for an app that attaches it itself, or composes it with
        # its own: returns <tt>[plugin, max_level, logger]</tt>, where
        # +plugin+ serves the page's <tt>log</tt> command, +logger+ is the
        # Logger the builder describes, made with +app_handle+ as
        # #build's setup makes it, and +max_level+ the lowest level it can
        # log, +:off+ when it has no targets (lib.rs:670-689; fern 0.7.1
        # builders.rs:589-595). The plugin has no setup, so it reads no
        # config.
        #
        # Raises Error::LoggerNotInitialized after #skip_logger, and the
        # target's error when a file target cannot be opened.
        #
        # === Example
        #
        #   plugin, max_level, logger = Tokra::Plugins::Log::Builder.new.split(app.handle)
        #   Tokra::Plugins::Log.attach_logger(max_level, logger)
        #   app.handle.plugin(plugin)
        def split(app_handle)
          raise Error::LoggerNotInitialized if @_skip_logger

          max_level, logger = acquire_logger(app_handle, settings)
          [plugin_builder.build, max_level, logger]
        end

        # :call-seq:
        #   with_colors(colors) -> raises NotImplementedError
        #
        # Raises NotImplementedError.
        #
        # == Why This Is Not Implemented
        #
        # Tauri's <tt>with_colors(ColoredLevelConfig)</tt> colors each level
        # with the +fern+ crate's +colors+ feature. Ruby's standard library
        # has no such configuration to take.
        #
        # == Alternatives
        #
        # Use a format that applies ANSI codes. The page's
        # <tt>attachLogger</tt> strips them, as it strips Tauri's:
        #
        #   COLORS = { warn: "\e[33m", error: "\e[31m" }.freeze
        #
        #   builder.format(Ractor.shareable_proc { |message, record|
        #     "#{COLORS[record.level]}[#{record.level.upcase}]\e[0m #{message}"
        #   })
        #
        # Or use gems like +rainbow+ or +pastel+ in your format.
        #
        # See: https://github.com/tauri-apps/plugins-workspace/blob/d4613ff0029ea65f5c6895c3a6f8f5668dd1b55e/plugins/log/src/lib.rs#L551-L565
        def with_colors(_colors)
          raise NotImplementedError,
            "with_colors is not implemented. Tauri uses fern's colors feature, which Ruby's standard " \
              "library lacks. Use Builder#format with a format that applies ANSI escape codes."
        end

        # Makes the plugin: a Tokra::Plugin::TauriPlugin named +log+, the
        # name in <tt>plugin:log|log</tt>, for Tokra::Builder#plugin, taking
        # no config.
        #
        # Its setup makes the Logger the builder describes, with the app's
        # handle, and attaches it as the process's logger with
        # Log.attach_logger, unless #skip_logger was called. LogDir targets
        # write in the app's +app_log_dir+, files are named for the app's
        # <tt>package_info.name</tt> unless their target names one, and
        # Webview targets emit through the app. A file target that cannot
        # be opened, or a second attach in one process, fails the app with
        # Tokra::Error::PluginInitialization. The settings are the
        # builder's when #build is called; changing the builder later
        # changes nothing, as Tauri's +build+ consumes the builder
        # (lib.rs:691-708).
        #
        # === Example
        #
        #   Tokra::Builder.default.plugin(Tokra::Plugins::Log::Builder.new.level(:info).build)
        def build
          settings = self.settings
          skip_logger = @_skip_logger
          plugin_builder
            .setup do |app_handle, _api|
              Log.attach_logger(*acquire_logger(app_handle, settings)) unless skip_logger
              nil
            end
            .build
        end

        # The builder's settings, as acquire_logger takes them.
        Settings = Data.define(:level, :filters, :format, :targets, :rotation_strategy, :timezone_strategy,
          :max_file_size)
        private_constant :Settings

        # A frozen copy of the builder's settings.
        private def settings
          Settings.new(level: @_level, filters: @_filters.dup.freeze, format: @_format,
            targets: @_targets.dup.freeze, rotation_strategy: @_rotation_strategy,
            timezone_strategy: @_timezone_strategy, max_file_size: @_max_file_size)
        end

        # The plugin both #build and #split make, before #build's setup:
        # named +log+, with the <tt>log</tt> command (lib.rs:666-668).
        private def plugin_builder
          Tokra::Plugin::Builder.new("log").invoke_handler { |invoke| handle_invoke(invoke) }
        end

        # Runs Commands.log for the <tt>log</tt> command and answers
        # whether it was that one, so Tokra rejects the rest with
        # <tt>Command NAME not found</tt>, as Tauri's generated handler
        # does. An argument that does not read rejects the invoke with
        # Tauri's message.
        private def handle_invoke(invoke)
          return false unless invoke.command == "log"

          Commands.log(invoke)
          true
        rescue Tokra::Error::InvalidArgs => e
          invoke.reject(e.message)
          true
        end

        # The lowest level the logger can log and the Logger itself, each
        # target's output opened with +app_handle+ (lib.rs:567-664; fern
        # 0.7.1 builders.rs:589-595, 634-641).
        private def acquire_logger(app_handle, settings)
          app_name = app_handle.package_info.name
          targets = []
          begin
            settings.targets.each do |target|
              targets << [target.filters.dup.freeze, target.formatter, output(target.kind, app_handle, app_name, settings)]
            end
          rescue
            # Rust drops the outputs already built when a later one fails.
            targets.each { |_filters, _format, output| output.drop }
            raise
          end
          max_level = targets.empty? ? :off : settings.level
          logger = Log::Logger.new(level: settings.level, filters: settings.filters, format: settings.format, app_name:,
            targets:)
          [max_level, logger]
        end

        # The output for +kind+ (lib.rs:587-657).
        private def output(kind, app_handle, app_name, settings)
          case kind
          when TargetKind::Stdout then Output::Stream.new(:stdout)
          when TargetKind::Stderr then Output::Stream.new(:stderr)
          when TargetKind::Folder then file_output(kind.path, kind.file_name || app_name, settings)
          when TargetKind::LogDir then file_output(app_handle.path.app_log_dir, kind.file_name || app_name, settings)
          when TargetKind::Webview then Output::Webview.new(app_handle)
          when TargetKind::Dispatch then Output::Dispatch.new(kind.logger)
          else raise ArgumentError, "unknown target kind: #{kind.inspect}"
          end
        end

        # A RotatingFile in +dir+, which is created first (lib.rs:613-641).
        private def file_output(dir, file_name, settings)
          FileUtils.mkdir_p(dir)
          Output::Writer.new(RotatingFile.new(dir, file_name, settings.max_file_size, settings.rotation_strategy,
            settings.timezone_strategy))
        end
      end
    end
  end
end

# SPDX-SnippetEnd
