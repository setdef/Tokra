# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Tokra
  module Ipc
    #--
    # SPDX-SnippetBegin
    # SPDX-License-Identifier: MIT OR Apache-2.0
    # SPDX-SnippetCopyrightText: Erick Tryzelaar and David Tolnay (serde, serde_json)
    # SPDX-SnippetComment: the descriptions of serde_core 1.0.228 de/mod.rs
    #   Unexpected as serde_json 1.0.140 src/value/de.rs:1395-1404 and
    #   src/error.rs JsonUnexpected produce them
    #++

    # Describes a JSON value the way serde_json's errors name it.
    #
    # Tauri's commands take typed arguments, and when the frontend sends
    # the wrong kind of value serde rejects the invoke with words like
    # <tt>invalid type: integer `1`, expected a string</tt>. The part
    # between "invalid type:" and "expected" names the value that arrived,
    # and its exact text depends on serde_json: integers in backticks,
    # floats as ryu prints them, strings quoted as Rust's Debug quotes
    # them, arrays as "sequence", objects as "map".
    #
    # This module writes that text, so a plugin's argument errors read as
    # Tauri's do. CommandItem uses it, and so does any plugin that checks
    # its own argument types. A plan 024 oracle, built from serde_json
    # itself, checked these descriptions on thousands of values.
    #
    # === Examples
    #
    #   Tokra::Ipc::Unexpected.describe(1)        #=> "integer `1`"
    #   Tokra::Ipc::Unexpected.describe(1.5)      #=> "floating point `1.5`"
    #   Tokra::Ipc::Unexpected.describe("x\n")    #=> "string \"x\\n\""
    #   Tokra::Ipc::Unexpected.describe([1])      #=> "sequence"
    module Unexpected
      # The range of integers serde_json reads as integers; it reads
      # larger ones as floats (serde_json de.rs, parse_integer).
      JSON_INTEGERS = -(2 ** 63)...(2 ** 64)

      # serde_json's description of +value+, a value JSON parsed: what an
      # <tt>invalid type</tt> error says arrived.
      #
      # === Example
      #
      #   Tokra::Ipc::Unexpected.describe(nil)  #=> "null"
      def self.describe(value)
        case value
        when nil then "null"
        when true, false then "boolean `#{value}`"
        when Integer then JSON_INTEGERS.cover?(value) ? "integer `#{value}`" : "floating point `#{float_text(value.to_f)}`"
        when Float then "floating point `#{float_text(value)}`"
        when String then "string #{debug(value)}"
        when Array then "sequence"
        else "map"
        end
      end

      #--
      # SPDX-SnippetEnd
      # SPDX-SnippetBegin
      # SPDX-License-Identifier: Apache-2.0
      # SPDX-SnippetCopyrightText: David Tolnay (ryu)
      # SPDX-SnippetComment: float_text adapted from ryu 1.0 src/pretty/mod.rs
      #   format64, licensed Apache-2.0 OR BSL-1.0, used here under Apache-2.0
      #++

      # A float as serde_json shows one, through ryu: the shortest digits,
      # as a decimal from 1e-5 to below 1e16 and with an exponent
      # otherwise, written <tt>1e16</tt> and <tt>1.5e-7</tt> (serde_json
      # error.rs JsonUnexpected, ryu 1.0 pretty/mod.rs format64).
      def self.float_text(float)
        return float.to_s if float.zero?

        digits, point = shortest_digits(float.abs)
        length = digits.length
        text = if point >= length && point <= 16
          "#{digits}#{'0' * (point - length)}.0"
        elsif point.positive? && point <= 16
          "#{digits[0, point]}.#{digits[point..]}"
        elsif point > -5 && point <= 0
          "0.#{'0' * -point}#{digits}"
        elsif length == 1
          "#{digits}e#{point - 1}"
        else
          "#{digits[0]}.#{digits[1..]}e#{point - 1}"
        end
        float.negative? ? "-#{text}" : text
      end
      private_class_method :float_text

      #--
      # SPDX-SnippetEnd
      #++

      # The shortest digits of positive +float+ and where its decimal
      # point falls: the value is 0.DIGITS times ten to that power.
      def self.shortest_digits(float)
        mantissa, exponent = float.to_s.split("e")
        whole, fraction = mantissa.to_s.split(".")
        whole = whole.to_s
        digits = "#{whole}#{fraction}"
        point = whole.length + exponent.to_i
        stripped = digits.sub(/\A0+/, "")
        point -= digits.length - stripped.length
        [stripped.sub(/0+\z/, ""), point]
      end
      private_class_method :shortest_digits

      #--
      # SPDX-SnippetBegin
      # SPDX-License-Identifier: MIT OR Apache-2.0
      # SPDX-SnippetCopyrightText: The Rust Project Developers
      # SPDX-SnippetComment: debug follows the rules of Rust's str Debug,
      #   char::escape_debug_ext and core/src/unicode/printable.py
      #++

      # Characters Rust's Debug escapes as <tt>\u{..}</tt>: grapheme
      # extenders, and what it does not print: controls, format characters,
      # surrogates, private use, unassigned code points, and every separator
      # but the space.
      UNPRINTABLE = /\p{Grapheme_Extend}|[\p{Cc}\p{Cf}\p{Cs}\p{Co}\p{Cn}\p{Zl}\p{Zp}[\p{Zs}&&[^ ]]]/

      # +string+ quoted as Rust's Debug quotes a str: escapes for quotes,
      # backslashes, tabs, returns, newlines, and NUL, and <tt>\u{..}</tt>
      # for UNPRINTABLE characters (char::escape_debug). Ruby's Unicode
      # tables stand in for Rust's, which may be a version apart.
      #
      # === Example
      #
      #   Tokra::Ipc::Unexpected.debug("tab\there")  #=> "\"tab\\there\""
      def self.debug(string)
        escaped = string.each_char.map do |char|
          case char
          when "\t" then "\\t"
          when "\r" then "\\r"
          when "\n" then "\\n"
          when "\\" then "\\\\"
          when '"' then "\\\""
          when "\0" then "\\0"
          else char.match?(UNPRINTABLE) ? format("\\u{%x}", char.ord) : char
          end
        end
        "\"#{escaped.join}\""
      end

      #--
      # SPDX-SnippetEnd
      #++
    end
  end
end
