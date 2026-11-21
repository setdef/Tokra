# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Tokra
  module Plugins
    module Log
      # Converts between Ruby Logger severity and Tauri LogLevel.
      #
      # Ruby Logger: TRACE=-1, DEBUG=0, INFO=1, WARN=2, ERROR=3, FATAL=4, UNKNOWN=5
      # Tauri:       Trace=1,  Debug=2, Info=3, Warn=4, Error=5
      #
      # Used for bidirectional communication:
      # - Ruby → Frontend (WebviewLogger emitting)
      # - Frontend → Ruby (log command receiving)
      module TauriLevel
        # Converts Ruby Logger severity to Tauri LogLevel (1-5).
        #
        # Formula: (severity + 2).clamp(1, 5)
        #
        # +severity+:: Ruby Logger severity (-1..5)
        # Returns:: Tauri LogLevel (1..5)
        def self.from_ruby(severity)
          (severity + 2).clamp(1, 5)
        end

        # Converts Tauri LogLevel to Ruby Logger severity.
        #
        # Formula: level - 2
        #
        # +level+:: Tauri LogLevel (1..5)
        # Returns:: Ruby Logger severity (-1..3)
        def self.to_ruby(level)
          level - 2
        end
      end
    end
  end
end
