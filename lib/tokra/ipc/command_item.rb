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
    # would, and raises Tokra::Error::InvalidArgs with Tauri's
    # <tt>invalid args `key` for command `name`: ...</tt> message and
    # serde_json's text. A plugin's extend_api rescues it and rejects the
    # invoke with that message. #string and #strings read a command's
    # String and Vec<String> arguments; #deserialize and
    # #deserialize_option read any other through a block that checks the
    # value, raising Mismatch where serde would fail.
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
    #   # raises Tokra::Error::InvalidArgs: invalid args `shortcuts` for command `register`:
    #   #   command register missing required key shortcuts
    class CommandItem < Data.define(:name, :key, :payload)
      # What serde_json said went wrong with a value, before InvalidArgs
      # wraps it: serde_json's +Error+ in this role.
      #
      # Raise it inside #deserialize or #deserialize_option, which turn it
      # into Tokra::Error::InvalidArgs for the argument.
      #
      # === Example
      #
      #   item.deserialize { |value| value == true || value == false ? value : raise(Mismatch.invalid_type(value, "a boolean")) }
      class Mismatch < StandardError
        # serde's <tt>invalid type</tt> error for +value+, a JSON value,
        # where +expected+ was wanted (serde de/mod.rs
        # Error::invalid_type), describing the value as serde_json does
        # (Unexpected).
        #
        # === Example
        #
        #   Mismatch.invalid_type(1, "a string").message  #=> "invalid type: integer `1`, expected a string"
        def self.invalid_type(value, expected)
          new("invalid type: #{Unexpected.describe(value)}, expected #{expected}")
        end
      end

      # The range of each Rust integer type an argument reads as.
      INTEGERS = { "u8" => 0..255, "u32" => 0..((2 ** 32) - 1), "i32" => -(2 ** 31)..((2 ** 31) - 1) }.freeze

      # +value+, a JSON value, as the Rust integer +type+ (<tt>"u8"</tt>,
      # <tt>"u32"</tt>, or <tt>"i32"</tt>), raising Mismatch with serde's
      # message where it does not fit: an integer out of range is an
      # invalid value, and anything else the wrong type, an integer too
      # large for serde_json, which reads it as a float, among them (serde
      # de/impls.rs, the primitive visitors).
      #
      # Call it inside #deserialize, for a field or an element; #u32 reads
      # a whole argument.
      #
      # === Example
      #
      #   Tokra::Ipc::CommandItem.integer(256, "u8")
      #   # raises Mismatch: invalid value: integer `256`, expected u8
      def self.integer(value, type)
        unless value.is_a?(Integer) && Unexpected::JSON_INTEGERS.cover?(value)
          raise Mismatch.invalid_type(value, type)
        end
        raise Mismatch, "invalid value: integer `#{value}`, expected #{type}" unless INTEGERS.fetch(type).cover?(value)

        value
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
        deserialize { |value| string_value(value) }
      end

      # The argument as a Rust +u32+, such as a ResourceId.
      #
      # === Example
      #
      #   Tokra::Ipc::CommandItem.new(name: "close", key: "rid", payload: { "rid" => 7 }).u32  #=> 7
      def u32
        deserialize { |value| CommandItem.integer(value, "u32") }
      end

      # The argument as a Rust <tt>Vec<String></tt>.
      #
      # === Example
      #
      #   Tokra::Ipc::CommandItem.new(name: "unregister", key: "shortcuts", payload: { "shortcuts" => ["F19"] }).strings  #=> ["F19"]
      def strings
        deserialize do |items|
          raise Mismatch.invalid_type(items, "a sequence") unless items.is_a?(Array)

          items.map { |item| string_value(item) }
        end
      end

      # The argument as the block reads it: the block receives the value
      # at #key and returns the argument, raising Mismatch when the value
      # is not one. A missing key raises serde_json's custom error
      # (command.rs:97-102), and a Mismatch becomes
      # Tokra::Error::InvalidArgs, as the CommandArg impl for every
      # deserializable type does (command.rs:60-70).
      #
      # === Example
      #
      #   item.deserialize { |value| value.is_a?(Hash) ? value : raise(Mismatch.invalid_type(value, "a map")) }
      def deserialize
        arguments = payload
        raise Mismatch, "command #{name} missing required key #{key}" unless arguments.key?(key)

        yield arguments[key]
      rescue Mismatch => e
        raise Error::InvalidArgs.new(name, key, e.message)
      end

      # The argument as a Rust <tt>Option</tt>: +nil+ when the key is
      # missing or null, and otherwise the value as the block reads it,
      # as for #deserialize (command.rs:134-145, and serde_json's
      # <tt>Value::deserialize_option</tt>).
      #
      # === Example
      #
      #   Tokra::Ipc::CommandItem.new(name: "write_text", key: "label", payload: {}).deserialize_option { |value| value }  #=> nil
      def deserialize_option
        return nil if payload[key].nil?

        deserialize { |value| yield value }
      end

      private def string_value(item)
        item.is_a?(String) ? item : raise(Mismatch.invalid_type(item, "a string"))
      end
    end
  end
end

# SPDX-SnippetEnd
