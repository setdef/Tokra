# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "logger"
require "pathname"

module Tokra
  module Plugins
    module Log
      # Configures a log output destination.
      #
      # Each Target wraps a destination (IO or Pathname) with optional
      # rotation settings. Only Pathname destinations support rotation.
      #
      # == Examples
      #
      #   # Console output (no rotation)
      #   Target.new($stdout)
      #
      #   # File with size-based rotation (3 files, 10MB each)
      #   Target.new(destination: Pathname("logs/app.log"), shift_age: 3, shift_size: 10_485_760)
      #
      #   # File with time-based rotation (daily)
      #   Target.new(destination: Pathname("logs/app.log"), shift_age: "daily")
      #
      # == Parameters
      #
      # +destination+::  +$stdout+, +$stderr+, or +Pathname+ for file output
      # +shift_age+::    rotation count or +'daily'+/+'weekly'+/+'monthly'+
      # +shift_size+::   max bytes before rotation (default: 1MB)
      # +level+::        minimum log level for this target (default: +:debug+)
      # +formatter+::    custom formatter proc (receives severity, time, progname, msg)
      #
      # == Errors
      #
      # Raises +ArgumentError+ if rotation params passed with IO destination.
      # Raises +Ractor::IsolationError+ if formatter is not Ractor-shareable.
      #
      class Target < Data.define(:destination, :shift_age, :shift_size, :level, :formatter)
        def initialize(destination:, shift_age: 0, shift_size: 1_048_576, level: :debug, formatter: nil)
          super
          validate_rotation_params!
          validate_formatter_shareable!
        end

        # Builds a TracingLogger instance for this target.
        def to_logger(_config = {})
          logger = case destination
          when Pathname then TracingLogger.new(destination.to_s, shift_age, shift_size)
          when IO, StringIO then TracingLogger.new(destination)
          else raise ArgumentError, "Unknown destination type: #{destination.class}"
          end
          logger.level = level_to_int(level)
          logger.formatter = formatter if formatter
          logger
        end

        private

        def level_to_int(lvl)
          case lvl
          when :trace then TRACE
          else lvl
          end
        end

        def validate_rotation_params!
          return if destination.is_a?(Pathname)
          return if shift_age == 0 && shift_size == 1_048_576 # defaults

          raise ArgumentError,
            "shift_age and shift_size only apply to Pathname destinations"
        end

        def validate_formatter_shareable!
          return unless formatter
          return if Ractor.shareable?(formatter)

          raise Ractor::IsolationError,
            "formatter must be Ractor-shareable (use Ractor.shareable_proc)"
        end
      end
    end
  end
end
