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
      # Plugin.
      #
      # With no changes, the plugin writes every level to standard output
      # and to the app's log directory, as
      # <tt>[2026-11-13][09:41:07][my-app][INFO] message</tt> in UTC, and
      # starts a log file over at 40000 bytes.
      #
      # Mirrors Tauri's <tt>tauri_plugin_log::Builder</tt> (lib.rs:395-709).
      #
      # === Examples
      #
      #   # Tauri's defaults
      #   Builder.new.app_handle(app.handle).build
      #
      #   # The terminal and the page's console, info and above
      #   Builder.new
      #     .app_handle(app.handle)
      #     .level(:info)
      #     .targets([
      #       Target.new(TargetKind::Stdout.new),
      #       Target.new(TargetKind::Webview.new),
      #     ])
      #     .build
      #
      #   # Local time, keeping the last five full files
      #   Builder.new
      #     .app_handle(app.handle)
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
          @_path_resolver = nil
          @_app_handle = nil
          @_app_name = nil
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

        # :call-seq:
        #   skip_logger -> raises NotImplementedError
        #
        # Raises NotImplementedError.
        #
        # == Why This Is Not Implemented
        #
        # Tauri's +skip_logger+ builds the plugin without a logger, so a
        # Rust app can install its own global logger, or register the
        # plugin twice in tests; the plugin's <tt>log</tt> command then
        # logs to whichever global logger the app installed. Ruby has no
        # global logger to install. A plugin that skipped its logger would
        # drop every record the page sends.
        #
        # == Alternatives
        #
        # Send the plugin's records to a Logger of your own:
        #
        #   builder.clear_targets.target(Target.new(TargetKind::Dispatch.new(my_logger)))
        #
        # See: https://github.com/tauri-apps/plugins-workspace/blob/d4613ff0029ea65f5c6895c3a6f8f5668dd1b55e/plugins/log/src/lib.rs#L519-L533
        def skip_logger
          raise NotImplementedError,
            "skip_logger is not implemented. Tauri skips its logger so a Rust app can install its own " \
              "global logger, and Ruby has no global logger. Use TargetKind::Dispatch to send the " \
              "plugin's records to a Logger of your own."
        end

        # :call-seq:
        #   split(app_handle) -> raises NotImplementedError
        #
        # Raises NotImplementedError.
        #
        # == Why This Is Not Implemented
        #
        # Tauri's +split+ hands back the plugin, its level, and its logger
        # apart, so a Rust app can combine the logger with others before it
        # installs one global logger. Ruby has no global logger to install,
        # and the Plugin is already the logger Ruby code calls.
        #
        # == Alternatives
        #
        # Log through the Plugin, and add a TargetKind::Dispatch target to
        # reach a Logger of your own.
        #
        # See: https://github.com/tauri-apps/plugins-workspace/blob/d4613ff0029ea65f5c6895c3a6f8f5668dd1b55e/plugins/log/src/lib.rs#L670-L689
        def split(_app_handle)
          raise NotImplementedError,
            "split is not implemented. Tauri splits its logger out so a Rust app can install it in a " \
              "global logger, and Ruby has no global logger. Log through the plugin, and use " \
              "TargetKind::Dispatch to reach a Logger of your own."
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

        # Sets the path resolver whose +app_log_dir+ a LogDir target writes
        # in. Without one, the app handle's is used.
        #
        # === Example
        #
        #   builder.path_resolver(app.handle.path)
        def path_resolver(resolver)
          @_path_resolver = resolver
          self
        end

        # Sets the app handle that Webview targets emit through and LogDir
        # targets find their directory and file name with, as Tauri's
        # plugin reads them from the app it is set up on (lib.rs:575, 628).
        #
        # === Example
        #
        #   builder.app_handle(app.handle)
        def app_handle(handle)
          @_app_handle = handle
          self
        end

        # Sets the app's name: the default target of Ruby records and the
        # default file name of Folder and LogDir targets. Without one, the
        # app handle's <tt>package_info.name</tt> is used.
        #
        # === Example
        #
        #   builder.app_name("my-app")
        def app_name(name)
          @_app_name = name
          self
        end

        # Makes the plugin, opening each target's file.
        #
        # Raises ArgumentError when a LogDir or Webview target has no app
        # handle to work with.
        #
        # === Example
        #
        #   app.handle.plugin(Builder.new.app_handle(app.handle).build)
        def build
          Plugin.new(self)
        end

        def configured_targets # :nodoc:
          @_targets
        end

        def configured_format # :nodoc:
          @_format
        end

        def configured_level # :nodoc:
          @_level
        end

        def configured_filters # :nodoc:
          @_filters
        end

        def configured_rotation_strategy # :nodoc:
          @_rotation_strategy
        end

        def configured_timezone_strategy # :nodoc:
          @_timezone_strategy
        end

        def configured_max_file_size # :nodoc:
          @_max_file_size
        end

        def configured_path_resolver # :nodoc:
          @_path_resolver
        end

        def configured_app_handle # :nodoc:
          @_app_handle
        end

        def configured_app_name # :nodoc:
          @_app_name
        end
      end
    end
  end
end

# SPDX-SnippetEnd
