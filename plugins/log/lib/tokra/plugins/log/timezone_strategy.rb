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
      # The clock a log line's timestamp and a rotated file's name read.
      #
      # Logs from a user's machine are easiest to line up with a server's
      # in UTC; logs you read at your own desk are easiest in local time.
      # The plugin stamps lines and names rotated files in UTC unless the
      # builder is given UseLocal. Builder#timezone_strategy also replaces
      # the line format with one in the chosen clock.
      #
      # Mirrors Tauri's +TimezoneStrategy+ (lib.rs:132-147). Rust cannot
      # always determine the local offset; UseLocal then falls back to UTC.
      #
      # === Examples
      #
      #   Builder.new.timezone_strategy(TimezoneStrategy::UseLocal.new)
      #   TimezoneStrategy::UseUtc.new.get_now.format(LOG_DATE_FORMAT)  #=> "2026-11-13_22-41-07"
      module TimezoneStrategy
        # Reads the clock in UTC.
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
        end

        # Reads the clock in the system's local offset.
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
        end
      end
    end
  end
end

# SPDX-SnippetEnd
