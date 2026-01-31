# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "logger"
require "pathname"
require "fileutils"

module Tokra
  module Plugins
    module Log
      # Configures a log output destination.
      #
      # Follows Tauri's fluent API pattern with mutable builder methods.
      #
      # == Examples
      #
      #   # Console output
      #   Target.new($stdout)
      #
      #   # File output
      #   Target.new(Pathname("logs/app.log"))
      #
      #   # With filter and formatter
      #   Target.new($stdout)
      #     .filter { |msg| !msg.include?("secret") }
      #     .format { |sev, time, prog, msg| "[#{sev}] #{msg}\n" }
      #
      # == Errors
      #
      # Raises +Ractor::IsolationError+ if filter/formatter is not Ractor-shareable.
      #
      # @see https://github.com/tauri-apps/plugins-workspace/blob/v2/plugins/log/src/lib.rs#L360-L393
      #
      class Target
        # The destination for log output.
        attr_reader :kind

        # Creates a new Target with the given kind.
        #
        # +kind+:: Pathname, IO, StringIO, or TargetKind::LogDir
        def initialize(kind)
          @kind = kind
          @filters = []
          @formatter = nil
        end

        # Adds a filter to this target. Returns self for chaining.
        #
        # +callback+:: a Ractor-shareable proc that receives the message
        #              and returns true to allow, false to block
        #
        def filter(callback = nil, &block)
          new_filter = callback || block
          validate_shareable!(new_filter, "filter")
          @filters << new_filter
          self
        end

        # Sets the formatter for this target. Returns self for chaining.
        #
        # +callback+:: a Ractor-shareable proc that receives (severity, time, progname, msg)
        #              and returns the formatted string
        #
        def format(callback = nil, &block)
          new_formatter = callback || block
          validate_shareable!(new_formatter, "formatter")
          @formatter = new_formatter
          self
        end

        # Builds a TracingLogger instance for this target.
        #
        # +config+:: configuration hash from Builder (level, rotation settings, etc)
        def to_logger(config = {})
          logger = create_base_logger(config)
          level = config.fetch(:level, :debug)
          logger.level = (level == :trace) ? TRACE : level
          logger.formatter = @formatter if @formatter
          wrap_with_filters(logger)
        end

        private def create_base_logger(config)
          shift_age = config.fetch(:shift_age, 0)
          shift_size = config.fetch(:shift_size, 1_048_576)

          case kind
          when Pathname then TracingLogger.new(kind.to_s, shift_age, shift_size)
          when IO, StringIO then TracingLogger.new(kind)
          when TargetKind::LogDir then create_log_dir_logger(config, shift_age, shift_size)
          else raise ArgumentError, "Unknown destination type: #{kind.class}"
          end
        end

        private def create_log_dir_logger(config, shift_age, shift_size)
          path_resolver = config.fetch(:path_resolver)
          log_dir = path_resolver.app_log_dir
          FileUtils.mkdir_p(log_dir)

          file_name = kind.file_name || config.fetch(:app_name, "app")
          log_path = log_dir.join("#{file_name}.log")
          TracingLogger.new(log_path.to_s, shift_age, shift_size)
        end

        private def wrap_with_filters(logger)
          @filters.reduce(logger) { |log, fltr| FilteringLogger.new(log, fltr) }
        end

        private def validate_shareable!(proc, name)
          return if proc.nil?
          return if Ractor.shareable?(proc)

          raise Ractor::IsolationError,
            "#{name} must be Ractor-shareable (use Ractor.shareable_proc)"
        end
      end

      # Logger wrapper that applies a filter to messages.
      class FilteringLogger
        # Creates a new FilteringLogger.
        #
        # +logger+:: the underlying logger to delegate to
        # +filter+:: a callable that returns true to allow the message
        def initialize(logger, filter)
          @logger = logger
          @filter = filter
        end

        # Adds a log entry if it passes the filter.
        def add(severity, message = nil, progname = nil)
          return unless @filter.call(message || progname)
          @logger.add(severity, message, progname)
        end

        %i[trace debug info warn error fatal].each do |level|
          define_method(level) do |message = nil, &block|
            msg = message || block&.call
            return unless @filter.call(msg)
            @logger.__send__(level, msg)
          end
        end

        # Writes raw message if it passes the filter.
        def <<(msg)
          return unless @filter.call(msg)
          @logger << msg
        end

        # Delegates unknown methods to the underlying logger.
        def method_missing(method, *, &)
          @logger.__send__(method, *, &)
        end

        # Returns true if the logger responds to the method.
        def respond_to_missing?(method, include_private = false)
          @logger.respond_to?(method, include_private)
        end
      end
      private_constant :FilteringLogger
    end
  end
end
