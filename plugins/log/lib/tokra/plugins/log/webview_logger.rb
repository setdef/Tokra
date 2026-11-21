# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: WebviewLogger adapted from tauri-plugin-log TargetKind::Webview

module Tokra
  module Plugins
    module Log
      # Logger that emits log events to WebView via AppHandle#emit.
      #
      # Emits "log://log" events with RecordPayload:
      #   { message: String, level: Integer }
      #
      # Level mapping (Ruby Logger → Tauri LogLevel):
      #   DEBUG=0 → 2, INFO=1 → 3, WARN=2 → 4, ERROR=3 → 5, FATAL=4 → 5
      #
      # Frontend subscribes via attachConsole() in guest-js.
      class WebviewLogger
        # TRACE constant matching TracingLogger.
        TRACE = -1

        # Level attribute (stub for Logger API compatibility).
        attr_accessor :level

        # Formatter attribute (stub for Logger API compatibility).
        attr_accessor :formatter

        # Creates a new WebviewLogger.
        #
        # +app_handle+:: AppHandle with #emit method.
        def initialize(app_handle)
          @app_handle = app_handle
          @level = 0 # Default to DEBUG
          @formatter = nil
        end

        # Logs a message at the given severity.
        #
        # +severity+:: Integer severity (Logger::DEBUG..Logger::FATAL)
        # +message+:: Optional message string
        # +progname+:: Optional program name (used as message if no block)
        # +block+:: Optional block that returns message
        def add(severity, message = nil, progname = nil, &block)
          msg = message || (block ? block.call : progname)
          level = TauriLevel.from_ruby(severity)
          @app_handle.emit("log://log", { message: msg.to_s, level: })
          true
        end

        # Logs a message at TRACE severity.
        def trace(message = nil, &)
          add(TRACE, message, nil, &)
        end

        # Logs a message at DEBUG severity.
        def debug(message = nil, &)
          add(0, message, nil, &)
        end

        # Logs a message at INFO severity.
        def info(message = nil, &)
          add(1, message, nil, &)
        end

        # Logs a message at WARN severity.
        def warn(message = nil, &)
          add(2, message, nil, &)
        end

        # Logs a message at ERROR severity.
        def error(message = nil, &)
          add(3, message, nil, &)
        end

        # Logs a message at FATAL severity.
        def fatal(message = nil, &)
          add(4, message, nil, &)
        end
      end
    end
  end
end

# SPDX-SnippetEnd
