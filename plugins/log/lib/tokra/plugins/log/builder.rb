# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Builder pattern adapted from plugins-workspace/plugins/log/src/lib.rs

module Tokra
  module Plugins
    module Log
      # Fluent Builder for configuring the Log plugin.
      #
      # Mirrors Tauri's +tauri_plugin_log::Builder+ API.
      #
      # Example:
      #   Log::Builder.new
      #     .targets([Target.new($stdout)])
      #     .level(:debug)
      #     .build
      #
      class Builder
        # Creates a new Builder with default configuration.
        def initialize
          @_targets = []
        end

        # Replaces the targets of the logger.
        def targets(targets)
          @_targets = targets
          self
        end

        # Adds a log target to the logger.
        def target(target)
          @_targets << target
          self
        end

        # Sets the global log level.
        def level(level)
          @_level = level
          self
        end

        # Sets the program name for log entries.
        def progname(name)
          @_progname = name
          self
        end

        # Sets the datetime format string (strftime).
        def datetime_format(format)
          @_datetime_format = format
          self
        end

        # Sets the rotation strategy for file targets.
        def rotation_strategy(strategy)
          @_rotation_strategy = strategy
          self
        end

        # Sets the timezone strategy for timestamps.
        def timezone_strategy(strategy)
          @_timezone_strategy = strategy
          self
        end

        # Sets the maximum file size for log rotation.
        def max_file_size(size)
          @_max_file_size = size
          self
        end

        # Removes all targets.
        #
        # Useful to ignore default targets and reconfigure.
        def clear_targets
          @_targets = []
          self
        end

        # Sets the global formatter for all targets.
        def format(formatter)
          @_formatter = formatter
          self
        end

        # Sets the global filter for all targets.
        #
        # Filter is a callable that receives the message and returns true to log.
        def filter(callable)
          @_filter = callable
          self
        end

        # Sets the path resolver for LogDir targets.
        def path_resolver(resolver)
          @_path_resolver = resolver
          self
        end

        # Sets the app handle for Webview targets.
        def app_handle(handle)
          @_app_handle = handle
          self
        end

        # Sets the app name for LogDir targets.
        def app_name(name)
          @_app_name = name
          self
        end

        # Skips creation of the global logger.
        #
        # Use if you provide your own global logger.
        def skip_logger
          @_skip_logger = true
          self
        end

        # :call-seq:
        #   with_colors(colors) -> raises NotImplementedError
        #
        # Raises NotImplementedError.
        #
        # == Why This Is Not Implemented
        #
        # Tauri's +with_colors(ColoredLevelConfig)+ uses the +fern+ crate's
        # +colors+ feature to apply ANSI escape sequences. Ruby's stdlib
        # +Logger+ has no built-in color support.
        #
        # == Alternatives
        #
        # Use a custom formatter that applies ANSI codes:
        #
        #   COLORS = { "DEBUG" => "\e[36m", "INFO" => "\e[32m",
        #              "WARN" => "\e[33m", "ERROR" => "\e[31m" }.freeze
        #   RESET = "\e[0m"
        #
        #   builder.format(Ractor.make_shareable(
        #     ->(sev, time, prog, msg) { "#{COLORS[sev]}[#{sev}]#{RESET} #{msg}\n" }
        #   ))
        #
        # Or use gems like +rainbow+ or +pastel+ in a custom formatter.
        #
        # See: https://github.com/tauri-apps/plugins-workspace/blob/v2/plugins/log/src/lib.rs#L551-565
        #
        def with_colors(_colors)
          raise NotImplementedError,
            "with_colors is not implemented. Tauri uses fern's colors feature, but Ruby's " \
              "Logger has no built-in color support. Use Builder#format with a custom " \
              "formatter that applies ANSI escape codes."
        end

        # Builds the configured log plugin.
        #
        # Returns a Plugin instance ready to be registered.
        def build
          Plugin.new(self)
        end

        # Consider these "friendly" -- public to Log plugin, private to app devs.
        # Uses underscore-prefixed ivars to avoid conflict with fluent setters.
        def configured_targets # :nodoc:
          @_targets
        end

        def configured_level # :nodoc:
          @_level
        end

        def configured_progname # :nodoc:
          @_progname
        end

        def configured_datetime_format # :nodoc:
          @_datetime_format
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

        def configured_skip_logger # :nodoc:
          @_skip_logger
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

        def configured_formatter # :nodoc:
          @_formatter
        end

        def configured_filter # :nodoc:
          @_filter
        end
      end
    end
  end
end

# SPDX-SnippetEnd
