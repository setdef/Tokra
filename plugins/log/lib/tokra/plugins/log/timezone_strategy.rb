# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: get_now adapted from tauri-plugin-log src/lib.rs

require "ferro/time"

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
          # The current date and time in UTC, from the time crate
          # (lib.rs:141).
          #
          # === Example
          #
          #   TimezoneStrategy::UseUtc.new.get_now  #=> 2026-11-13 22:41:07.0 +00:00:00
          def get_now
            Ferro::Time::OffsetDateTime.now_utc
          end

          ##
          # Formats the time in UTC.
          def format_time(time)
            time.utc
          end
        end

        # Use local timezone for timestamps (Ruby default).
        #
        # Pass-through, no conversion.
        class UseLocal < Data.define
          # The current date and time in the system's local offset, or in
          # UTC when the time crate cannot determine the offset, as
          # Tauri's does (lib.rs:142-144).
          #
          # === Example
          #
          #   TimezoneStrategy::UseLocal.new.get_now  #=> 2026-11-13 16:41:07.0 -06:00:00
          def get_now
            Ferro::Time::OffsetDateTime.now_local
          rescue Ferro::Time::Error::IndeterminateOffset
            Ferro::Time::OffsetDateTime.now_utc
          end

          ##
          # Returns time unchanged (already local).
          def format_time(time)
            time
          end
        end
      end
    end
  end
end

# SPDX-SnippetEnd
