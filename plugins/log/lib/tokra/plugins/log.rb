# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "tokra"
require "logger"
require_relative "log/tracing_logger"
require_relative "log/tauri_level"
require_relative "log/webview_logger"
require_relative "log/rotation_strategy"
require_relative "log/timezone_strategy"
require_relative "log/target"
require_relative "log/target_kind"
require_relative "log/builder"

module Tokra
  module Plugins
    # Namespace for the log plugin.
    #
    # Use Tokra::Plugins::Log::Plugin as the plugin class.
    module Log
      # Logging plugin for Tokra desktop applications.
      #
      # Wraps Ruby's Logger with desktop-friendly defaults and
      # integrates with Tokra's plugin lifecycle.
      #
      # == Example
      #
      #   Tokra::Builder.new
      #     .plugin(Tokra::Plugins::Log::Plugin.new(app, level: :info))
      #     .run
      #
      class Plugin < Tokra::Plugin
        # Returns the unique plugin identifier.
        def name
          "log"
        end

        # Initializes the logging plugin from a Builder.
        #
        # +builder+:: configured Builder instance
        def initialize(builder)
          @progname = builder.configured_progname
          @datetime_format = builder.configured_datetime_format
          @loggers = build_loggers(builder)
        end

        # :call-seq:
        #   level_for(mod, level) -> raises NotImplementedError
        #
        # Raises NotImplementedError.
        #
        # == Why This Is Not Implemented
        #
        # Tauri's +level_for(module, level)+ filters log messages by
        # Rust module path (e.g., +hyper::client+). This works because
        # Rust's +log+ crate provides compile-time module metadata via
        # +log::Record::target()+, which defaults to the module path.
        #
        # Ruby has no equivalent metadata:
        #
        # - Ruby Logger's +progname+ is rarely set by libraries
        # - ActiveRecord, ActiveJob, Rack accept progname in signatures
        #   but don't pass identifying values (just API compatibility)
        # - Sinatra, Grape, SQLite3-Ruby, Roda don't use progname at all
        # - Hanami supports progname in templates (app-level, not self-ID)
        # - There's no automatic module/class context in log calls
        #
        # == Alternatives
        #
        # Use Target's +filter+ callback for message-based filtering:
        #
        #   target.filter(->(msg) { !msg.include?("CACHE") })
        #
        # Or use per-library loggers:
        #
        #   ActiveRecord::Base.logger = quiet_logger
        #
        # See: https://github.com/tauri-apps/plugins-workspace/blob/d4613ff0029ea65f5c6895c3a6f8f5668dd1b55e/plugins/log/src/lib.rs#L488-491
        #
        def level_for(_module_name, _level)
          raise NotImplementedError,
            "level_for is not implemented. Tauri's level_for filters by Rust module path " \
              "metadata that Ruby lacks. Use Target#filter callbacks for message-based filtering."
        end

        # Logs a trace message (lowest priority).
        def trace(message) = log(TRACE, message)

        # Logs a debug message.
        def debug(message) = log(:debug, message)

        # Logs an info message.
        def info(message) = log(:info, message)

        # Logs a warning message.
        def warn(message) = log(:warn, message)

        # Logs an error message.
        def error(message) = log(:error, message)

        # Logs a fatal message.
        def fatal(message) = log(:fatal, message)

        # Logs a message using Logger's add API.
        #
        # +level+::    severity level (integer or symbol)
        # +message+::  the log message
        # +progname+:: optional program name override for this entry
        def add(level, message = nil, progname = nil)
          @loggers.each { |logger| logger.add(level, message, progname) }
        end

        # Writes a raw message without formatting.
        def <<(message)
          @loggers.each { |logger| logger << message }
        end

        # Temporarily adjusts log level for the duration of a block.
        #
        # +level+:: the level to use within the block
        #
        # See Logger#with_level (Ruby 3.3+).
        def with_level(level)
          @loggers.each { |logger| logger.with_level(level) { yield } }
        end

        # Dispatches a log message at the specified level to all loggers.
        private def log(level, message) # :nodoc:
          if level.is_a?(Integer)
            @loggers.each { |logger| logger.add(level, message) }
          else
            @loggers.each { |logger| logger.__send__(level, message) }
          end
        end

        # Builds Logger instances from the configured targets.
        private def build_loggers(builder) # :nodoc:
          targets = builder.configured_targets
          targets = [Target.new($stdout)] if targets.empty?
          global_formatter = builder.configured_formatter
          global_filter = builder.configured_filter
          targets.map do |target|
            logger = target.to_logger(builder)
            logger.progname = @progname if @progname
            logger.datetime_format = @datetime_format if @datetime_format
            logger.formatter = global_formatter if global_formatter && !logger.formatter
            logger = FilteringLogger.new(logger, global_filter) if global_filter
            logger
          end
        end
      end
    end
  end
end
