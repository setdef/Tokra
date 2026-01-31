# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "tokra"
require "logger"
require_relative "log/tracing_logger"
require_relative "log/target"

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

        # Initializes the logging plugin.
        #
        # +app+::    the application handle
        # +config+:: plugin configuration hash
        #
        # Config options:
        # - +:level+:: log level (+:debug+, +:info+, +:warn+, +:error+, +:fatal+)
        # - +:targets+:: array of Target instances for log output
        def initialize(app, config = {})
          super
          @loggers = build_loggers(config)
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

        # Dispatches a log message at the specified level to all loggers.
        private def log(level, message) # :nodoc:
          if level.is_a?(Integer)
            @loggers.each { |logger| logger.add(level, message) }
          else
            @loggers.each { |logger| logger.__send__(level, message) }
          end
        end

        # Builds Logger instances from the configured targets.
        private def build_loggers(config) # :nodoc:
          targets = config.fetch(:targets, [Target.new($stdout)])
          targets.map { |target| target.to_logger(config) }
        end
      end
    end
  end
end
