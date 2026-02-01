# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Tokra
  module Plugins
    module Log
      # Controls timestamp timezone in log entries (Tauri API parity).
      #
      # Plugin-level setting passed to formatters.
      #
      # == Usage
      #
      #   Builder.new.timezone_strategy(TimezoneStrategy::UseUtc.new)
      #
      module TimezoneStrategy
        # Use UTC for all timestamps.
        #
        # Converts local time to UTC.
        class UseUtc < Data.define
          ##
          # Formats the time in UTC.
          def format_time(time) = time.utc
        end

        # Use local timezone for timestamps (Ruby default).
        #
        # Pass-through, no conversion.
        class UseLocal < Data.define
          ##
          # Returns time unchanged (already local).
          def format_time(time) = time
        end
      end
    end
  end
end
