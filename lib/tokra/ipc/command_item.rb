# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetCopyrightText: Erick Tryzelaar and David Tolnay (serde, serde_json)
# SPDX-SnippetComment: CommandItem adapted from tauri/crates/tauri/src/ipc/command.rs
#                      and the InvalidArgs message from error.rs:59-60; the type
#                      messages are serde's as serde_json produces them

module Tokra
  module Ipc
    # One named argument of a command, read the way Tauri deserializes it.
    #
    # A Tauri command declares typed arguments, and serde turns each key of
    # the frontend's payload into its type, or rejects the invoke with a
    # precise message: a missing key, or the wrong kind of value. The
    # frontend's error handling, and a developer reading the console,
    # depend on those words.
    #
    # This class reads one key of an invoke's payload as the Rust type
    # would, and raises ArgumentError with Tauri's <tt>invalid args `key`
    # for command `name`: ...</tt> message and serde_json's text. A plugin's
    # extend_api rejects the invoke with that message. Use it for the
    # String and Vec<String> arguments of a command.
    #
    # Mirrors Tauri's +CommandItem+ deserializer (ipc/command.rs:60-130) and
    # <tt>Error::InvalidArgs</tt> (error.rs:59-60). +name+ is the command's
    # name, +key+ the argument's, and +payload+ the invoke's payload.
    #
    # === Examples
    #
    #   item = Tokra::Ipc::CommandItem.new(name: "register", key: "shortcuts", payload: invoke.payload)
    #   item.strings  #=> ["CmdOrCtrl+Shift+K"]
    #
    #   Tokra::Ipc::CommandItem.new(name: "register", key: "shortcuts", payload: {}).strings
    #   # raises ArgumentError: invalid args `shortcuts` for command `register`:
    #   #   command register missing required key shortcuts
    class CommandItem < Data.define(:name, :key, :payload)
      # What serde_json said went wrong, before InvalidArgs wraps it.
      class Mismatch < StandardError # :nodoc:
      end

      # :attr_reader: name
      # The command's name, as Tauri's <tt>CommandItem::name</tt>.

      # :attr_reader: key
      # The argument's key in the payload, as <tt>CommandItem::key</tt>.

      # :attr_reader: payload
      # The invoke's payload, a Hash with String keys.

      # The argument as a Rust +String+.
      #
      # === Example
      #
      #   Tokra::Ipc::CommandItem.new(name: "is_registered", key: "shortcut", payload: { "shortcut" => "F19" }).string  #=> "F19"
      def string
        deserialize { string_value(value) }
      end

      # The argument as a Rust <tt>Vec<String></tt>.
      #
      # === Example
      #
      #   Tokra::Ipc::CommandItem.new(name: "unregister", key: "shortcuts", payload: { "shortcuts" => ["F19"] }).strings  #=> ["F19"]
      def strings
        deserialize do
          items = value
          invalid_type(items, "a sequence") unless items.is_a?(Array)
          items.map { |item| string_value(item) }
        end
      end

      # Runs the block, turning a Mismatch into Tauri's InvalidArgs message
      # (error.rs:59-60).
      private def deserialize
        yield
      rescue Mismatch => e
        raise ArgumentError, "invalid args `#{key}` for command `#{name}`: #{e.message}"
      end

      # The value at +key+, or serde_json's custom missing-key error
      # (command.rs:97-102).
      private def value
        arguments = payload
        return arguments[key] if arguments.key?(key)

        raise Mismatch, "command #{name} missing required key #{key}"
      end

      private def string_value(item)
        item.is_a?(String) ? item : invalid_type(item, "a string")
      end

      # serde's <tt>invalid type</tt> error (de/mod.rs Error::invalid_type).
      private def invalid_type(item, expected)
        raise Mismatch, "invalid type: #{Unexpected.describe(item)}, expected #{expected}"
      end
    end
  end
end

# SPDX-SnippetEnd
