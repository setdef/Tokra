# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "json"

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Callback formatting adapted from tauri/crates/tauri/src/ipc/format_callback.rs

module Tokra
  module Ipc
    # Formats invoke responses as JavaScript callback evaluations.
    #
    # An invoke's promise lives in the WebView; Ruby holds the result.
    # The only road back is evaluating JavaScript, and building that
    # JavaScript by hand risks breaking on quotes, backslashes, or
    # payloads large enough to choke the JS parser.
    #
    # This module produces the exact script Tauri produces:
    # <tt>window.__TAURI_INTERNALS__.runCallback(id, arg)</tt>, where
    # +arg+ is the JSON value inlined as a literal — or, for objects and
    # arrays past 10 KiB, wrapped in <tt>JSON.parse('...')</tt>, which
    # engines parse faster than large literals. Mirrors
    # format_callback.rs.
    #
    # === Example
    #
    #   Tokra::Ipc::FormatCallback.format(42, {"ok" => true})
    #   #=> "window.__TAURI_INTERNALS__.runCallback(42, {\"ok\":true})"
    module FormatCallback
      # Minimum JSON size that benefits from JSON.parse
      # (format_callback.rs MIN_JSON_PARSE_LEN).
      MIN_JSON_PARSE_LEN = 10_240

      # Maximum safe JavaScript string literal size
      # (format_callback.rs MAX_JSON_STR_LEN).
      MAX_JSON_STR_LEN = (2 ** 30) - 2

      # Formats a callback ID and a serializable value as an eval-ready
      # script.
      #
      # Matches format_callback.rs +format+.
      #
      # === Example
      #
      #   Tokra::Ipc::FormatCallback.format(7, nil)
      #   #=> "window.__TAURI_INTERNALS__.runCallback(7, null)"
      def self.format(callback_id, value)
        format_raw(callback_id, JSON.generate(value))
      end

      # Formats a callback ID and a raw JSON string as an eval-ready
      # script.
      #
      # Objects and arrays larger than MIN_JSON_PARSE_LEN bytes (not
      # characters: Rust's len() counts bytes) render as
      # <tt>JSON.parse('...')</tt> with backslashes and single quotes
      # escaped; everything else is inlined as a literal. Matches
      # format_callback.rs +format_raw+ and +serialize_js_with+.
      #
      # === Example
      #
      #   Tokra::Ipc::FormatCallback.format_raw(7, '"pong"')
      #   #=> 'window.__TAURI_INTERNALS__.runCallback(7, "pong")'
      def self.format_raw(callback_id, json_string)
        first = json_string[0]
        arg = json_string
        if json_string.bytesize > MIN_JSON_PARSE_LEN && (first == "{" || first == "[")
          parsed = "JSON.parse('#{escape(json_string)}')"
          arg = parsed if parsed.bytesize < MAX_JSON_STR_LEN
        end
        "window.__TAURI_INTERNALS__.runCallback(#{callback_id}, #{arg})"
      end

      # Formats a callback ID and a JavaScript expression as an eval-ready
      # script, with no JSON handling: +js+ goes in as it is. Channels use
      # it for their <tt>{ message, index }</tt> objects. Matches
      # format_callback.rs +format_raw_js+ (format_callback.rs:100-106).
      #
      # === Example
      #
      #   Tokra::Ipc::FormatCallback.format_raw_js(7, "{ end: true, index: 0 }")
      #   #=> "window.__TAURI_INTERNALS__.runCallback(7, { end: true, index: 0 })"
      def self.format_raw_js(callback_id, js)
        "window.__TAURI_INTERNALS__.runCallback(#{callback_id}, #{js})"
      end

      # Escapes a JSON string for a single-quoted JavaScript literal.
      #
      # Backslashes first, then single quotes — the same two characters
      # serialize_to_javascript escapes.
      def self.escape(json)
        json.gsub("\\") { "\\\\" }.gsub("'") { "\\'" }
      end
      private_class_method :escape
    end
  end
end

# SPDX-SnippetEnd
