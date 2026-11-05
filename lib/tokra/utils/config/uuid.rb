# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2013-2014 The Rust Project Developers; 2018 The Uuid Project Developers
# SPDX-SnippetComment: uuid 1.11.0 (the version Tauri's lock pins): src/parser.rs:19-30,
#   :82-130, :138-237 (Uuid::parse_str, try_parse, parse_simple,
#   parse_hyphenated), src/error.rs:52-172 (InvalidUuid::into_err and the
#   Display of Error), src/external/serde_support.rs:57-75 (the human-readable
#   Deserialize)
#++

module Tokra
  module Utils
    module Config
      # Reads +value+, a JSON value, as the uuid crate's Deserialize reads a
      # <tt>uuid::Uuid</tt> from serde_json: a string in any of the four
      # forms <tt>Uuid::parse_str</tt> takes, simple, hyphenated, braced
      # (<tt>{...}</tt>), or URN (<tt>urn:uuid:...</tt>), in either case of
      # hex digit. Answers the UUID as uuid's Display writes it, hyphenated
      # and lowercase, frozen: Ruby has no UUID type, and that String is
      # what serde writes the value back as.
      #
      # A string uuid refuses fails with its words, <tt>UUID parsing
      # failed: {error}</tt>, and anything else is the wrong type, expected
      # <tt>a UUID string</tt> (serde_support.rs:57-75).
      def self.uuid(value) # :nodoc:
        raise Ipc::CommandItem::Mismatch.invalid_type(value, "a UUID string") unless value.is_a?(String)

        hex = Uuid.parse(value)
        "#{hex[0, 8]}-#{hex[8, 4]}-#{hex[12, 4]}-#{hex[16, 4]}-#{hex[20, 12]}".freeze
      end

      # uuid 1.11.0's parser and its errors (parser.rs, error.rs).
      module Uuid # :nodoc:
        HEX = /\A\h*\z/
        URN = "urn:uuid:"
        # Where each group of a hyphenated UUID starts (error.rs:126).
        BLOCK_STARTS = [0, 9, 14, 19, 24].freeze
        GROUP_LENGTHS = [8, 4, 4, 4, 12].freeze

        # The 32 hex digits of +input+, lowercase, or uuid's error.
        def self.parse(input)
          hex, invalid = try_parse(input.b)
          raise Ipc::CommandItem::Mismatch, "UUID parsing failed: #{error(invalid.to_s.dup.force_encoding(Encoding::UTF_8))}" unless hex

          hex.downcase
        end

        # try_parse (parser.rs:82-101): 32 bytes are simple, and 36, a
        # braced 38, or a URN of 45 are hyphenated. Answers the hex digits,
        # or +nil+ and the bytes uuid's InvalidUuid holds: the whole input
        # when its shape is wrong, and only what is inside the braces or
        # after the URN prefix when that part fails.
        def self.try_parse(bytes)
          inner = case bytes.bytesize
            when 32, 36 then bytes
            when 38 then bytes[1..-2].to_s if bytes.start_with?("{") && bytes.end_with?("}")
            when 45 then bytes.delete_prefix(URN) if bytes.start_with?(URN)
          end
          return [nil, bytes] unless inner

          hex = (inner.bytesize == 32) ? simple(inner) : hyphenated(inner)
          hex ? [hex, nil] : [nil, inner]
        end

        def self.simple(bytes)
          bytes if HEX.match?(bytes)
        end

        # parse_hyphenated (parser.rs:139-180): hyphens at 8, 13, 18, and
        # 23, and hex digits everywhere else.
        def self.hyphenated(bytes)
          return unless [8, 13, 18, 23].all? { |index| bytes[index] == "-" }

          digits = bytes.delete("-")
          digits if digits.bytesize == 32 && HEX.match?(digits)
        end

        # InvalidUuid::into_err (error.rs:52-128), worded as Error's Display
        # (error.rs:131-165), for the bytes InvalidUuid holds. A JSON string
        # is UTF-8, and so is any part of one that try_parse cuts at an
        # ASCII byte, so its InvalidUTF8 arm never runs.
        def self.error(input)
          uuid, offset, simple = if input.start_with?("{") && input.end_with?("}") && input.bytesize >= 2
            [input[1..-2].to_s, 1, false]
          elsif input.start_with?(URN)
            [input.delete_prefix(URN), URN.bytesize, false]
          else
            [input, 0, true]
          end
          hyphens = [] #: Array[Integer]
          index = 0
          uuid.each_char do |character|
            if character == "-"
              hyphens << index
            elsif !character.match?(/\h/)
              return "invalid character: expected an optional prefix of `urn:uuid:` followed by [0-9a-fA-F-], " \
                "found `#{character}` at #{index + offset + 1}"
            end
            index += character.bytesize
          end
          return "invalid length: expected length 32 for simple format, found #{input.bytesize}" if hyphens.empty? && simple
          return "invalid group count: expected 5, found #{hyphens.size + 1}" unless hyphens.size == 4

          group_length(hyphens, offset, input)
        end

        # The first group of five whose length is wrong (error.rs:112-127).
        # The last group's length counts from +input+'s start, braces or URN
        # prefix included, as uuid counts it.
        def self.group_length(hyphens, offset, input)
          group = (0...4).find { |group| hyphens.fetch(group) != BLOCK_STARTS.fetch(group + 1) - 1 }
          length = group ? hyphens.fetch(group) - BLOCK_STARTS.fetch(group) : input.bytesize - BLOCK_STARTS.fetch(4)
          group ||= 4
          "invalid group length in group #{group}: expected #{GROUP_LENGTHS.fetch(group)}, found #{length}"
        end
        private_class_method :try_parse, :simple, :hyphenated, :error, :group_length
      end
    end
  end
end

#--
# SPDX-SnippetEnd
#++
