# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Commands adapted from tauri-plugin-log src/commands.rs

module Tokra
  module Plugins
    module Log
      # The plugin's one command, which <tt>@tauri-apps/plugin-log</tt>'s
      # +trace+, +debug+, +info+, +warn+, and +error+ invoke as
      # <tt>plugin:log|log</tt>.
      #
      # Mirrors Tauri's <tt>commands.rs</tt>.
      module Commands
        # The range of Rust's u16, which LogLevel deserializes through.
        U16 = 0..65_535
        private_constant :U16

        # Logs the page's message at its LogLevel to Log.logger, the
        # process's logger, with the target <tt>webview:<location></tt>,
        # or WEBVIEW_TARGET when the page names no location, and resolves
        # +null+ (commands.rs:11-41). With no logger attached, as after
        # Builder#skip_logger, the record goes nowhere, as Tauri's goes to
        # the log crate's no-op logger.
        #
        # Arguments read as Tauri's types: +level+ as serde_repr reads
        # LogLevel, +message+ a String, +location+ and +file+ an
        # <tt>Option<&str></tt>, +line+ an <tt>Option<u32></tt>, and
        # +keyValues+ an <tt>Option<HashMap<String, String>></tt>. One that
        # does not read raises Tokra::Error::InvalidArgs with Tauri's
        # message.
        #
        # === Example
        #
        #   // In the page
        #   import { warn } from "@tauri-apps/plugin-log";
        #   await warn("slow paint", { keyValues: { frame: "12" } });
        def self.log(invoke)
          level = log_level_arg(invoke)
          message = argument(invoke, "message").string
          location = optional_str_arg(invoke, "location")
          file = optional_str_arg(invoke, "file")
          line = argument(invoke, "line").deserialize_option { |value| Ipc::CommandItem.integer(value, "u32") }
          key_values = key_values_arg(invoke)
          target = location ? "#{WEBVIEW_TARGET}:#{location}" : WEBVIEW_TARGET
          Log.logger.log(Record.new(args: message, level:, target:, file:, line:, key_values: key_values || {}))
          invoke.resolve(nil)
        end

        # Argument +key+ of the invoke, read as Tauri's CommandItem reads it.
        def self.argument(invoke, key) # :nodoc:
          Ipc::CommandItem.new(name: invoke.command, key:, payload: invoke.body)
        end

        # The level, read as serde_repr reads LogLevel: a u16, then one of
        # its discriminants (serde_repr 0.1.20 lib.rs:101-118).
        def self.log_level_arg(invoke) # :nodoc:
          argument(invoke, "level").deserialize do |value|
            unless value.is_a?(Integer) && Ipc::Unexpected::JSON_INTEGERS.cover?(value)
              raise Ipc::CommandItem::Mismatch.invalid_type(value, "u16")
            end
            raise Ipc::CommandItem::Mismatch, "invalid value: integer `#{value}`, expected u16" unless U16.cover?(value)
            unless LogLevel::LEVELS.key?(value)
              raise Ipc::CommandItem::Mismatch, "invalid value: #{value}, expected one of: 1, 2, 3, 4, 5"
            end

            LogLevel.to_level(value)
          end
        end

        # An Option<&str> argument: absent or null is +nil+.
        def self.optional_str_arg(invoke, key) # :nodoc:
          argument(invoke, key).deserialize_option do |value|
            value.is_a?(String) ? value : raise(Ipc::CommandItem::Mismatch.invalid_type(value, "a borrowed string"))
          end
        end

        # The Option<HashMap<String, String>> of key-value pairs.
        def self.key_values_arg(invoke) # :nodoc:
          argument(invoke, "keyValues").deserialize_option do |value|
            raise Ipc::CommandItem::Mismatch.invalid_type(value, "a map") unless value.is_a?(Hash)

            value.each_value do |item|
              raise Ipc::CommandItem::Mismatch.invalid_type(item, "a string") unless item.is_a?(String)
            end
            value
          end
        end
        private_class_method :argument, :log_level_arg, :optional_str_arg, :key_values_arg
      end
    end
  end
end

# SPDX-SnippetEnd
