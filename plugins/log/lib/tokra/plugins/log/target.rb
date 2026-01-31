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
      #   Target.new(Pathname("logs/app.log"), shift_age: 3, shift_size: 10_485_760)
      #
      #   # File with time-based rotation (daily)
      #   Target.new(Pathname("logs/app.log"), shift_age: "daily")
      #
      class Target
        # Creates a new log target.
        #
        # +destination+::  +$stdout+, +$stderr+, or +Pathname+ for file output
        # +shift_age+::    rotation count or +'daily'+/+'weekly'+/+'monthly'+
        # +shift_size+::   max bytes before rotation (default: 1MB)
        # +level+::        minimum log level for this target (default: +:debug+)
        #
        # Raises +ArgumentError+ if rotation params passed with IO destination.
        def initialize(destination, shift_age: 0, shift_size: 1_048_576, level: :debug)
          validate_rotation_params!(destination, shift_age, shift_size)
          @destination = destination
          @shift_age = shift_age
          @shift_size = shift_size
          @level = level
        end

        # Builds a Logger instance for this target.
        def to_logger(_config = {})
          logger = case @destination
          when Pathname then Logger.new(@destination.to_s, @shift_age, @shift_size)
          when IO, StringIO then Logger.new(@destination)
          else raise ArgumentError, "Unknown destination type: #{@destination.class}"
          end
          logger.level = @level
          logger
        end

        private def validate_rotation_params!(destination, shift_age, shift_size)
          return if destination.is_a?(Pathname)
          return if shift_age == 0 && shift_size == 1_048_576 # defaults

          # IO destinations don't support rotation
          raise ArgumentError,
            "shift_age and shift_size only apply to Pathname destinations"
        end
      end
    end
  end
end
