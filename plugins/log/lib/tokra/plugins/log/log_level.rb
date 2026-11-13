# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: LogLevel adapted from tauri-plugin-log src/lib.rs

module Tokra
  module Plugins
    module Log
      # The verbosity levels as numbers, the form a level takes between
      # Ruby and the page.
      #
      # Inside the plugin a level is one of log's names: +:error+, +:warn+,
      # +:info+, +:debug+, or +:trace+. On the wire it is a number, 1 for
      # Trace up to 5 for Error, which <tt>@tauri-apps/plugin-log</tt>
      # sends with the <tt>log</tt> command and reads from each
      # <tt>log://log</tt> event. This module holds those numbers and
      # converts between the two forms.
      #
      # Mirrors Tauri's +LogLevel+ (lib.rs:70-120), which serializes to
      # unsigned integers where log's +Level+ serializes to strings.
      #
      # === Example
      #
      #   Tokra::Plugins::Log::LogLevel.from(:warn)   #=> 4
      #   Tokra::Plugins::Log::LogLevel.to_level(4)   #=> :warn
      module LogLevel
        # The "trace" level: very low priority, often extremely verbose,
        # information.
        TRACE = 1

        # The "debug" level: lower priority information.
        DEBUG = 2

        # The "info" level: useful information.
        INFO = 3

        # The "warn" level: hazardous situations.
        WARN = 4

        # The "error" level: very serious errors.
        ERROR = 5

        # Each level's name by its number.
        LEVELS = { TRACE => :trace, DEBUG => :debug, INFO => :info, WARN => :warn, ERROR => :error }.freeze

        # The number of +level+, a level name, as Tauri's
        # <tt>From<log::Level> for LogLevel</tt> (lib.rs:110-120).
        #
        # === Example
        #
        #   LogLevel.from(:error)  #=> 5
        def self.from(level)
          LEVELS.key(level) || raise(ArgumentError, "unknown level: #{level.inspect}")
        end

        # The level name of +log_level+, a number from 1 to 5, as Tauri's
        # <tt>From<LogLevel> for log::Level</tt> (lib.rs:98-108).
        #
        # === Example
        #
        #   LogLevel.to_level(1)  #=> :trace
        def self.to_level(log_level)
          LEVELS.fetch(log_level)
        end
      end
    end
  end
end

# SPDX-SnippetEnd
