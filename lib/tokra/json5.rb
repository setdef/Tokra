# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Tokra
  #--
  # SPDX-SnippetBegin
  # SPDX-License-Identifier: ISC
  # SPDX-SnippetCopyrightText: 2018 Callum Oakley (json5)
  # SPDX-SnippetComment: a port of json5 0.4.1 from_str::<serde_json::Value>:
  #   src/de.rs:16-69 (from_str, deserialize_any) and :251-399 (parse_bool,
  #   parse_string_component, parse_char_escape_sequence, parse_number,
  #   parse_integer, is_int, parse_hex, is_hex_literal, is_infinite,
  #   is_nan), src/error.rs (Error, Location, set_location)
  #++

  # Reads JSON5 text as Tauri reads a JSON5 config.
  #
  # A config written as <tt>tokra.conf.json5</tt> may hold comments,
  # unquoted keys, single-quoted strings, trailing commas, hexadecimal
  # numbers, <tt>Infinity</tt>, and <tt>NaN</tt>. Tauri reads it with the
  # json5 crate (0.4.1, the version its lock pins), into a
  # <tt>serde_json::Value</tt>, and reads every <tt>tokra.conf.json</tt>
  # with it first too (tauri-utils src/config/parse.rs:288-300). What
  # json5 accepts, the values it gives, and the words it fails with are
  # what a Tauri developer sees, and no Ruby gem gives the same.
  #
  # This module is json5's grammar and deserializer, ported step for step
  # with the pest parser machinery its syntax errors come from (plan 054,
  # decision 17). It answers what <tt>json5::from_str::<Value></tt>
  # answers:
  #
  # - An integer literal, hexadecimal included, is an Integer; any other
  #   number is a Float. <tt>-0</tt> is the Integer 0.
  # - <tt>NaN</tt>, <tt>Infinity</tt>, and <tt>-Infinity</tt> are +nil+,
  #   as serde_json's Value takes them.
  # - Each object's keys are in byte order, as serde_json's map keeps
  #   them, and a repeated key keeps its last value.
  # - Nesting has no limit, as json5's has none; the parser keeps its own
  #   stack, so deep nesting does not reach Ruby's.
  #
  # A syntax error reads as pest renders it; a value json5 cannot convert
  # reads in json5's words, such as <tt>error parsing hex</tt>.
  #
  # Mirrors the json5 crate's <tt>from_str</tt> (json5 0.4.1 src/de.rs).
  #
  # === Examples
  #
  #   Tokra::Json5.from_str("{b: 0x10, a: [1, 2,], // done\n}")  #=> {"a" => [1, 2], "b" => 16}
  #   Tokra::Json5.from_str("{")
  #   # raises Tokra::Json5::Error, " --> 1:2\n  |\n1 | {\n  |  ^---\n  |\n  = expected identifier or string"
  module Json5
    # Raised when json5 rejects the text.
    #
    # The message is json5's: pest's rendering of a syntax error, with its
    # line, column, source line, and the rules it expected, or the
    # deserializer's own words for a value it cannot convert.
    #
    # Mirrors json5's <tt>Error::Message</tt> (src/error.rs:26-38).
    #
    # === Example
    #
    #   begin
    #     Tokra::Json5.from_str("0x100000000")
    #   rescue Tokra::Json5::Error => e
    #     e.message   #=> "error parsing hex"
    #     e.location  #=> #<data Tokra::Json5::Location line=1, column=1>
    #   end
    class Error < Tokra::Error
      # Where the error was found, a Location, or +nil+.
      attr_reader :location

      # [message] the error's text.
      # [location] a Location, or +nil+.
      def initialize(message, location = nil)
        @location = location
        super(message)
      end
    end

    # The one-based line and column at which an Error was found.
    #
    # Mirrors json5's <tt>Location</tt> (src/error.rs:10-24).
    #
    # === Example
    #
    #   Tokra::Json5::Location.new(line: 2, column: 5)
    class Location < Data.define(:line, :column)
    end

    # The value json5 reads from +text+, a UTF-8 String, as serde_json's
    # Value holds it: Hashes with String keys, Arrays, Integers, Floats,
    # Strings, +true+, +false+, and +nil+. Raises Error when json5 rejects
    # the text, ArgumentError for text that is not valid in its encoding
    # (Rust's &str holds only UTF-8), and Encoding::UndefinedConversionError
    # for text UTF-8 cannot hold. Text in another encoding is converted to
    # UTF-8 first.
    #
    # Mirrors json5's <tt>from_str::<serde_json::Value></tt>
    # (src/de.rs:18-24).
    #
    # === Example
    #
    #   Tokra::Json5.from_str("[+1, .5, 'two', NaN]")  #=> [1, 0.5, "two", nil]
    def self.from_str(text)
      text = String.try_convert(text) || raise(TypeError, "no implicit conversion of #{text.class} into String")
      raise ArgumentError, "invalid byte sequence in #{text.encoding}" unless text.valid_encoding?

      Parser.new(text.encode(Encoding::UTF_8)).parse
    end

    # The deserializer's half of json5: what each leaf of a parsed text
    # becomes, and the words it fails with (src/de.rs:251-399).
    module De # :nodoc:
      # The escapes json5 turns into control characters
      # (parse_char_escape_sequence, de.rs:337-347); any other escaped
      # character is itself.
      CHAR_ESCAPES = { "b" => "\b", "f" => "\f", "n" => "\n", "r" => "\r", "t" => "\t", "v" => "\v" }.freeze

      U32_MAX = (2 ** 32) - 1
      I64_RANGE = (-(2 ** 63))..((2 ** 63) - 1)

      # The decimal forms Rust's <tt>str::parse::<f64></tt> reads, as far
      # as json5's grammar lets one through: a sign, digits with an
      # optional fraction or a fraction alone, and an exponent.
      DECIMAL = /\A([+-]?)(?:(\d+)(?:\.(\d*))?|\.(\d+))(?:[eE]([+-]?\d+))?\z/

      # The least magnitude that rounds to infinity, f64::MAX plus half
      # its last place, and the greatest that rounds to zero, half the
      # least subnormal; both round as an IEEE 754 parse rounds, to even.
      OVERFLOW = Rational((2 ** 1024) - (2 ** 970))
      UNDERFLOW = Rational(1, 2 ** 1075)

      # The Value json5 gives a <tt>number</tt>: an integer literal as an
      # Integer, anything else as a Float, and a float serde_json cannot
      # hold, NaN or an infinity, as +nil+ (deserialize_any, de.rs:56-62).
      # Raises Error with json5's words.
      def self.number(text)
        return parse_integer(text) if int?(text)

        number = parse_number(text)
        number.finite? ? number : nil
      end

      # json5's string, from the components the grammar matched: each an
      # escape's or a character's rule and its text. A UTF-16 lead
      # surrogate takes the next component as its trail, whatever its rule
      # (parse_string_component, de.rs:259-328).
      def self.string(components)
        result = +""
        index = 0
        while index < components.size
          rule, text = components.fetch(index)
          index += 1
          case rule
          when :char_literal then result << text
          when :char_escape_sequence then result << CHAR_ESCAPES.fetch(text, text)
          when :nul_escape_sequence then result << "\u0000"
          when :hex_escape_sequence then result << parse_hex(text).chr(Encoding::UTF_8)
          else
            code, index = unicode_escape(components, text, index)
            result << code.chr(Encoding::UTF_8)
          end
        end
        result
      end

      # The code point a <tt>\u</tt> escape names, joining a surrogate pair
      # as json5 joins one, and the index of the component after it.
      #
      # json5 0.4.1 writes the join as
      # <tt>((rc1 - 0xD800) << 10) | (rc2 - 0xDC00) + 0x1_0000</tt>, where
      # Rust's <tt>+</tt> binds before <tt>|</tt>, so the pair's 0x10000
      # is or'd into the lead's bits rather than added, and a lead whose
      # offset from 0xD800 has its 0x40 bit set joins to the wrong code
      # point: <tt>"\uD840\uDC00"</tt> reads U+10000, not U+20000. Tokra
      # joins it the same way.
      def self.unicode_escape(components, text, index)
        lead = parse_hex(text)
        raise Error, "unexpected unicode trail surrogate" if (0xDC00..0xDFFF).cover?(lead)
        return [lead, index] unless (0xD800..0xDBFF).cover?(lead)

        following = components[index]
        raise Error, "missing unicode trail surrogate" unless following

        trail = parse_hex(following.fetch(1))
        raise Error, "expecting unicode trail surrogate" unless (0xDC00..0xDFFF).cover?(trail)

        [((lead - 0xD800) << 10) | ((trail - 0xDC00) + 0x1_0000), index + 1]
      end

      # Whether json5 reads +text+ as an integer (is_int, de.rs:378-383).
      def self.int?(text)
        !text.include?(".") && (hex_literal?(text) || (!text.include?("e") && !text.include?("E"))) &&
          !%w[Infinity -Infinity NaN -NaN].include?(text)
      end

      # +text+ as an <tt>i64</tt>: hexadecimal through a <tt>u32</tt>,
      # anything else as Rust parses an <tt>i64</tt> (parse_integer,
      # de.rs:369-376).
      def self.parse_integer(text)
        return parse_hex(text[2..].to_s) if hex_literal?(text)

        integer = text.match?(/\A[+-]?\d+\z/) ? Integer(text, 10) : nil
        raise Error, "error parsing integer" unless integer && I64_RANGE.cover?(integer)

        integer
      end

      # +text+ as an <tt>f64</tt> (parse_number, de.rs:349-367).
      def self.parse_number(text)
        case text
        when "Infinity" then Float::INFINITY
        when "-Infinity" then -Float::INFINITY
        when "NaN", "-NaN" then Float::NAN
        else
          return parse_hex(text[2..].to_s).to_f if hex_literal?(text)

          number = parse_f64(text)
          raise Error, "error parsing number" unless number
          raise Error, "error parsing number: too large" unless number.finite?

          number
        end
      end

      # +text+ as Rust's <tt>str::parse::<f64></tt> reads a decimal,
      # rounded to nearest, or +nil+ when Rust refuses it. A magnitude
      # past f64's range is infinite and one below it zero, decided
      # exactly, so Ruby's <tt>Float()</tt> never warns of a range it
      # would leave.
      def self.parse_f64(text)
        match = DECIMAL.match(text)
        return nil unless match

        sign, whole, fraction, alone, exponent = match.captures
        fraction ||= alone || ""
        digits = "#{whole}#{fraction}".sub(/\A0+/, "")
        return (sign == "-") ? -0.0 : 0.0 if digits.empty?

        scale = exponent.to_i - fraction.size
        magnitude = scale + digits.size - 1
        infinite = magnitude > 308
        zero = magnitude < -324
        if magnitude == 308 || magnitude == -324
          exact = Rational(Integer(digits, 10)) * (Rational(10) ** scale)
          infinite = exact >= OVERFLOW
          zero = exact <= UNDERFLOW
        end
        return (sign == "-") ? -Float::INFINITY : Float::INFINITY if infinite
        return (sign == "-") ? -0.0 : 0.0 if zero

        Float("#{sign}#{digits}e#{scale}")
      end

      # +text+, hexadecimal digits, as a <tt>u32</tt> (parse_hex,
      # de.rs:385-387).
      def self.parse_hex(text)
        value = text.match?(/\A\h+\z/) ? text.to_i(16) : nil
        raise Error, "error parsing hex" unless value && value <= U32_MAX

        value
      end

      # Whether +text+ starts with <tt>0x</tt> or <tt>0X</tt> and has more
      # after it (is_hex_literal, de.rs:389-391).
      def self.hex_literal?(text)
        text.size > 2 && (text.start_with?("0x") || text.start_with?("0X"))
      end
    end

    #--
    # SPDX-SnippetEnd
    #++
  end
end

require_relative "json5/pest"
require_relative "json5/parser"
