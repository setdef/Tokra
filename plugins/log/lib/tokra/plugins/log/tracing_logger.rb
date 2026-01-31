# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "logger"

module Tokra
  module Plugins
    module Log
      # TRACE severity level, below DEBUG.
      #
      # Ruby's Logger lacks TRACE, so we define it as -1.
      # This matches Tauri's log plugin API which includes trace.
      TRACE = -1

      # Logger subclass with TRACE level support.
      #
      # Overrides format_severity to return "TRACE" for severity -1.
      # This is the minimal change needed to support TRACE without
      # monkey-patching the global Logger class.
      #
      # == Usage
      #
      #   logger = Tokra::Plugins::Log::TracingLogger.new($stdout)
      #   logger.level = Tokra::Plugins::Log::TRACE
      #   logger.add(Tokra::Plugins::Log::TRACE, "very verbose")
      #
      class TracingLogger < ::Logger
        # Logs a trace message (lowest priority).
        def trace(progname = nil, &block)
          add(TRACE, nil, progname, &block)
        end

        # Returns true if TRACE messages would be logged.
        def trace?
          level <= TRACE
        end

        # Sets log level to TRACE.
        def trace!
          self.level = TRACE
        end

        private

        # Converts severity to label, with TRACE support.
        def format_severity(severity)
          return "TRACE" if severity == TRACE
          super
        end
      end
    end
  end
end
