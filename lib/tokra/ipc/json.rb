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
    # SPDX-SnippetCopyrightText: Erick Tryzelaar and David Tolnay (serde_json)
    # SPDX-SnippetComment: a port of serde_json 1.0.145 from_slice::<Value>
    #   with the raw_value feature Tauri enables: src/de.rs (Deserializer,
    #   SeqAccess, MapAccess, MapKey, from_trait), src/read.rs (SliceRead,
    #   parse_escape, parse_unicode_escape), src/error.rs (ErrorCode
    #   Display, make_error), src/value/de.rs (ValueVisitor, KeyClassifier)
    #   and src/raw.rs (BoxedFromString)
    #++

    # Parses an invoke body the way Tauri's serde_json does.
    #
    # Tauri reads every invoke with serde_json: an ipc:// body with
    # <tt>serde_json::from_slice::<Value></tt> (ipc/protocol.rs:525-538),
    # a postMessage with <tt>serde_json::from_str</tt>
    # (ipc/protocol.rs:287-291). A body serde_json rejects never reaches a
    # command, and the page sees serde_json's own words, such as
    # <tt>lone leading surrogate in hex escape at line 1 column 13</tt>.
    # Ruby's JSON accepts bytes serde_json rejects: invalid UTF-8 inside a
    # string, a lone trailing surrogate escape, comments, numbers too big
    # for a double. Those bodies reached commands as broken strings and
    # failed deep inside a plugin with Ruby's words instead.
    #
    # This module is serde_json's parser, ported step for step, so a body
    # is accepted or rejected as Tauri accepts or rejects it, with the same
    # message and position. Its values are serde_json's too: an integer
    # beyond 64 bits and <tt>-0</tt> become floats, and floats round as
    # serde_json rounds them without its float_roundtrip feature.
    #
    # === Example
    #
    #   Tokra::Ipc::Json.parse('{"a":[1,-0]}')  #=> {"a" => [1, -0.0]}
    #   Tokra::Ipc::Json.parse('"\ud800"')
    #   # raises Tokra::Ipc::Json::Error,
    #   #   "unexpected end of hex escape at line 1 column 8"
    module Json # :nodoc:
      # Raised when serde_json would reject the input. The message is
      # serde_json's Display: the reason and, for a syntax error, its line
      # and column (error.rs:405-417).
      class Error < Tokra::Error
      end

      # serde_json's error descriptions (error.rs:349-384).
      EOF_WHILE_PARSING_LIST = "EOF while parsing a list"
      EOF_WHILE_PARSING_OBJECT = "EOF while parsing an object" # :nodoc:
      EOF_WHILE_PARSING_STRING = "EOF while parsing a string" # :nodoc:
      EOF_WHILE_PARSING_VALUE = "EOF while parsing a value" # :nodoc:
      EXPECTED_COLON = "expected `:`" # :nodoc:
      EXPECTED_LIST_COMMA_OR_END = "expected `,` or `]`" # :nodoc:
      EXPECTED_OBJECT_COMMA_OR_END = "expected `,` or `}`" # :nodoc:
      EXPECTED_SOME_IDENT = "expected ident" # :nodoc:
      EXPECTED_SOME_VALUE = "expected value" # :nodoc:
      INVALID_ESCAPE = "invalid escape" # :nodoc:
      INVALID_NUMBER = "invalid number" # :nodoc:
      NUMBER_OUT_OF_RANGE = "number out of range" # :nodoc:
      INVALID_UNICODE_CODE_POINT = "invalid unicode code point" # :nodoc:
      CONTROL_CHARACTER_WHILE_PARSING_STRING =
        "control character (\\u0000-\\u001F) found while parsing a string" # :nodoc:
      KEY_MUST_BE_A_STRING = "key must be a string" # :nodoc:
      LONE_LEADING_SURROGATE_IN_HEX_ESCAPE = "lone leading surrogate in hex escape" # :nodoc:
      TRAILING_COMMA = "trailing comma" # :nodoc:
      TRAILING_CHARACTERS = "trailing characters" # :nodoc:
      UNEXPECTED_END_OF_HEX_ESCAPE = "unexpected end of hex escape" # :nodoc:
      RECURSION_LIMIT_EXCEEDED = "recursion limit exceeded" # :nodoc:

      # How deep arrays and objects may nest: serde_json counts down from
      # 128 and fails when it reaches zero (de.rs:63, 1370-1385).
      RECURSION_LIMIT = 128

      # The first object key that makes serde_json, with raw_value, read
      # the entry's value as the JSON text of a string (raw.rs:299,
      # value/de.rs:131-135).
      RAW_VALUE_TOKEN = "$serde_json::private::RawValue"

      # serde_json's POW10 table, the exact doubles 1e0 through 1e308
      # (de.rs:1304-1337).
      POW10 = Array.new(309) { |exponent| "1e#{exponent}".to_f }.freeze

      U64_MAX = (2 ** 64) - 1 # :nodoc:
      I32_MAX = (2 ** 31) - 1 # :nodoc:

      # Bytes a string's fast scan stops at: a quote, a backslash, or a
      # control character (read.rs:432-491, 836-838).
      STRING_STOP = /["\\\x00-\x1f]/n

      # The value serde_json reads from +source+, a String of any encoding
      # whose bytes are the JSON text. Raises Json::Error with serde_json's
      # message when serde_json would reject it (de.rs:2495-2506).
      #
      # === Example
      #
      #   Tokra::Ipc::Json.parse("[1, 2.5]")  #=> [1, 2.5]
      def self.parse(source)
        Parser.new(source).parse
      end

      # One pass of serde_json's Deserializer over a SliceRead: the input
      # bytes, the read index, and the remaining recursion depth.
      class Parser # :nodoc:
        def initialize(source)
          @bytes = source.b
          @index = 0
          @remaining_depth = RECURSION_LIMIT
        end

        # Deserializes one value, then requires nothing but whitespace
        # after it (from_trait, de.rs:2495-2506; end, de.rs:143-148).
        def parse
          value = parse_value
          raise peek_error(TRAILING_CHARACTERS) if parse_whitespace

          value
        end

        private def peek
          @bytes.getbyte(@index)
        end

        private def peek_or_null
          peek || 0
        end

        private def eat_char
          @index += 1
        end

        private def next_char
          byte = @bytes.getbyte(@index)
          @index += 1 if byte
          byte
        end

        # The line and column of byte +index+: lines count from one, and
        # the column is the number of bytes since the line began
        # (read.rs:421-430).
        private def position_of(index)
          newline = index.zero? ? nil : @bytes.rindex("\n", index - 1)
          start_of_line = newline ? newline + 1 : 0
          [1 + @bytes.byteslice(0, start_of_line).to_s.count("\n"), index - start_of_line]
        end

        # An error at the read position (de.rs:241-246, read.rs:573-575).
        private def error(reason)
          error_at(reason, @index)
        end

        # An error one byte past the read position, capped at the end
        # (de.rs:248-253, read.rs:577-581).
        private def peek_error(reason)
          error_at(reason, [@bytes.bytesize, @index + 1].min)
        end

        private def error_at(reason, index)
          line, column = position_of(index)
          Error.new("#{reason} at line #{line} column #{column}")
        end

        private def parse_whitespace
          bytes = @bytes
          index = @index
          while (byte = bytes.getbyte(index))
            break unless byte == 0x20 || byte == 0x0a || byte == 0x09 || byte == 0x0d

            index += 1
          end
          @index = index
          byte
        end

        # deserialize_any with ValueVisitor (de.rs:1391-1465).
        private def parse_value
          byte = parse_whitespace
          raise peek_error(EOF_WHILE_PARSING_VALUE) unless byte

          case byte
          when 0x6e then parse_keyword("ull", nil) # n
          when 0x74 then parse_keyword("rue", true) # t
          when 0x66 then parse_keyword("alse", false) # f
          when 0x2d # -
            eat_char
            parse_integer(false)
          when 0x30..0x39 then parse_integer(true)
          when 0x22 # "
            eat_char
            parse_str
          when 0x5b then nested { parse_seq } # [
          when 0x7b then nested { parse_map } # {
          else raise peek_error(EXPECTED_SOME_VALUE)
          end
        end

        private def parse_keyword(rest, value)
          eat_char
          parse_ident(rest)
          value
        end

        # check_recursion (de.rs:1370-1385).
        private def nested
          @remaining_depth -= 1
          raise peek_error(RECURSION_LIMIT_EXCEEDED) if @remaining_depth.zero?

          eat_char
          value = yield
          @remaining_depth += 1
          value
        end

        private def parse_ident(ident)
          ident.each_byte do |expected|
            byte = next_char
            raise error(EOF_WHILE_PARSING_VALUE) unless byte
            raise error(EXPECTED_SOME_IDENT) unless byte == expected
          end
        end

        # ValueVisitor#visit_seq over SeqAccess, then end_seq
        # (value/de.rs:107-119; de.rs:1928-1972, 1070-1086). The visitor
        # reads every element, so end_seq always finds the bracket.
        private def parse_seq
          values = [] #: Array[json_value]
          first = true
          loop do
            byte = parse_whitespace
            raise peek_error(EOF_WHILE_PARSING_LIST) unless byte
            break if byte == 0x5d # ]

            if first
              first = false
            elsif byte == 0x2c # ,
              eat_char
              case parse_whitespace
              when 0x5d then raise peek_error(TRAILING_COMMA)
              when nil then raise peek_error(EOF_WHILE_PARSING_VALUE)
              end
            else
              raise peek_error(EXPECTED_LIST_COMMA_OR_END)
            end
            values << parse_value
          end
          eat_char
          values
        end

        # ValueVisitor#visit_map over MapAccess, then end_map
        # (value/de.rs:121-148; de.rs:1981-2033, 1088-1098).
        private def parse_map
          first_key = next_key(true)
          return end_map({}) unless first_key

          if first_key == RAW_VALUE_TOKEN
            parse_object_colon
            return end_map(parse_raw_value)
          end

          values = {} #: Hash[String, json_value]
          key = first_key #: String?
          while key
            parse_object_colon
            values[key] = parse_value
            key = next_key(false)
          end
          # Value's Map is a BTreeMap without preserve_order: its keys
          # iterate in byte order, the last duplicate kept (map.rs:22-26).
          end_map(values.sort.to_h)
        end

        # has_next_key and MapKey#deserialize_any (de.rs:1988-2021,
        # 2203-2214): the next key, or nil at the closing brace.
        private def next_key(first)
          byte = parse_whitespace
          raise peek_error(EOF_WHILE_PARSING_OBJECT) unless byte
          return nil if byte == 0x7d # }

          if first
            raise peek_error(KEY_MUST_BE_A_STRING) unless byte == 0x22
          elsif byte == 0x2c # ,
            eat_char
            case parse_whitespace
            when 0x22 then nil
            when 0x7d then raise peek_error(TRAILING_COMMA)
            when nil then raise peek_error(EOF_WHILE_PARSING_VALUE)
            else raise peek_error(KEY_MUST_BE_A_STRING)
            end
          else
            raise peek_error(EXPECTED_OBJECT_COMMA_OR_END)
          end
          eat_char
          parse_str
        end

        private def parse_object_colon
          case parse_whitespace
          when 0x3a then eat_char # :
          when nil then raise peek_error(EOF_WHILE_PARSING_OBJECT)
          else raise peek_error(EXPECTED_COLON)
          end
        end

        # end_map after the visitor returns (de.rs:1088-1098). After a raw
        # value the visitor stops at its first entry, so a comma here is a
        # trailing comma, as serde_json reports it.
        private def end_map(value)
          case parse_whitespace
          when 0x7d then eat_char # }
          when 0x2c then raise peek_error(TRAILING_COMMA)
          when nil then raise peek_error(EOF_WHILE_PARSING_OBJECT)
          else raise peek_error(TRAILING_CHARACTERS)
          end
          value
        end

        # BoxedFromString through deserialize_str, then serde_json::from_str
        # of the string's text (raw.rs:433-466; de.rs:1522-1549;
        # value/de.rs:131-135). An inner error keeps its own position:
        # make_error reads it back out of the message (error.rs:483-534).
        private def parse_raw_value
          byte = parse_whitespace
          raise peek_error(EOF_WHILE_PARSING_VALUE) unless byte
          raise invalid_raw_value(byte) unless byte == 0x22

          eat_char
          Parser.new(parse_str).parse
        end

        # peek_invalid_type for the raw value visitor, positioned by
        # fix_position at the read index (de.rs:269-316, 441-443).
        private def invalid_raw_value(byte)
          unexpected = case byte
          when 0x6e then parse_keyword("ull", nil)
          when 0x74 then parse_keyword("rue", true)
          when 0x66 then parse_keyword("alse", false)
          when 0x2d
            eat_char
            parse_integer(false)
          when 0x30..0x39 then parse_integer(true)
          when 0x5b then [] #: Array[json_value]
          when 0x7b then {} #: Hash[String, json_value]
          else return peek_error(EXPECTED_SOME_VALUE)
          end
          error("invalid type: #{Unexpected.describe(unexpected)}, expected raw value")
        end

        # parse_integer (de.rs:462-507).
        private def parse_integer(positive)
          byte = next_char
          raise error(EOF_WHILE_PARSING_VALUE) unless byte

          case byte
          when 0x30
            raise peek_error(INVALID_NUMBER) if digit?(peek_or_null)

            parse_number(positive, 0)
          when 0x31..0x39
            significand = byte - 0x30
            bytes = @bytes
            while (byte = bytes.getbyte(@index)) && byte.between?(0x30, 0x39)
              digit = byte - 0x30
              return parse_long_integer(positive, significand) if overflow?(significand, digit, U64_MAX)

              @index += 1
              significand = (significand * 10) + digit
            end
            parse_number(positive, significand)
          else
            raise error(INVALID_NUMBER)
          end
        end

        # parse_number (de.rs:509-528): an integer when it fits, and a
        # float for <tt>-0</tt> and negatives below i64::MIN.
        private def parse_number(positive, significand)
          case peek_or_null
          when 0x2e then parse_decimal(positive, significand, 0)
          when 0x65, 0x45 then parse_exponent(positive, significand, 0)
          else
            if positive
              significand
            elsif significand.zero? || significand > 2 ** 63
              -significand.to_f
            else
              -significand
            end
          end
        end

        # parse_decimal (de.rs:530-565).
        private def parse_decimal(positive, significand, exponent_before_decimal_point)
          eat_char
          exponent_after_decimal_point = 0
          bytes = @bytes
          while (byte = bytes.getbyte(@index)) && byte.between?(0x30, 0x39)
            digit = byte - 0x30
            if overflow?(significand, digit, U64_MAX)
              exponent = exponent_before_decimal_point + exponent_after_decimal_point
              return parse_decimal_overflow(positive, significand, exponent)
            end

            eat_char
            significand = (significand * 10) + digit
            exponent_after_decimal_point -= 1
          end

          if exponent_after_decimal_point.zero?
            raise peek_error(peek ? INVALID_NUMBER : EOF_WHILE_PARSING_VALUE)
          end

          exponent = exponent_before_decimal_point + exponent_after_decimal_point
          if exponent?(peek_or_null)
            parse_exponent(positive, significand, exponent)
          else
            f64_from_parts(positive, significand, exponent)
          end
        end

        # parse_exponent (de.rs:567-621).
        private def parse_exponent(positive, significand, starting_exp)
          eat_char
          sign = peek_or_null
          eat_char if sign == 0x2b || sign == 0x2d # + -
          positive_exp = sign != 0x2d

          byte = next_char
          raise error(EOF_WHILE_PARSING_VALUE) unless byte
          raise error(INVALID_NUMBER) unless digit?(byte)

          exp = byte - 0x30
          while digit?(peek_or_null)
            digit = peek_or_null - 0x30
            eat_char
            if overflow?(exp, digit, I32_MAX)
              return parse_exponent_overflow(positive, significand.zero?, positive_exp)
            end

            exp = (exp * 10) + digit
          end

          # serde_json saturates this sum at the i32 bounds; any exponent
          # past POW10 takes the same path, so Ruby's unbounded sum agrees.
          f64_from_parts(positive, significand, positive_exp ? starting_exp + exp : starting_exp - exp)
        end

        # f64_from_parts without float_roundtrip (de.rs:637-675):
        # the significand times or divided by a power of ten, which can
        # differ from the correctly rounded double in the last place.
        private def f64_from_parts(positive, significand, exponent)
          float = significand.to_f
          loop do
            pow = POW10[exponent.abs]
            if pow
              if exponent >= 0
                float *= pow
                raise error(NUMBER_OUT_OF_RANGE) if float.infinite?
              else
                float /= pow
              end
              break
            end
            break if float.zero?
            raise error(NUMBER_OUT_OF_RANGE) if exponent >= 0

            float /= 1e308
            exponent += 308
          end
          positive ? float : -float
        end

        # parse_long_integer without float_roundtrip (de.rs:714-735).
        private def parse_long_integer(positive, significand)
          exponent = 0
          loop do
            case peek_or_null
            when 0x30..0x39
              eat_char
              exponent += 1
            when 0x2e then return parse_decimal(positive, significand, exponent)
            when 0x65, 0x45 then return parse_exponent(positive, significand, exponent)
            else return f64_from_parts(positive, significand, exponent)
            end
          end
        end

        # parse_decimal_overflow without float_roundtrip (de.rs:835-855).
        private def parse_decimal_overflow(positive, significand, exponent)
          eat_char while digit?(peek_or_null)
          if exponent?(peek_or_null)
            parse_exponent(positive, significand, exponent)
          else
            f64_from_parts(positive, significand, exponent)
          end
        end

        # parse_exponent_overflow (de.rs:857-874).
        private def parse_exponent_overflow(positive, zero_significand, positive_exp)
          raise error(NUMBER_OUT_OF_RANGE) if !zero_significand && positive_exp

          eat_char while digit?(peek_or_null)
          positive ? 0.0 : -0.0
        end

        # The overflow! macro: whether value * 10 + digit exceeds limit
        # (de.rs:101-107).
        private def overflow?(value, digit, limit)
          return false if value < limit / 10

          value > limit / 10 || digit > limit % 10
        end

        private def digit?(byte)
          byte.between?(0x30, 0x39)
        end

        private def exponent?(byte)
          byte == 0x65 || byte == 0x45 # e E
        end

        # SliceRead#parse_str_bytes with validation, after the opening
        # quote (read.rs:494-542, 868-870): the string up to its closing
        # quote with escapes decoded, which must be UTF-8.
        private def parse_str
          scratch = nil #: String?
          start = @index
          loop do
            @index = @bytes.byteindex(STRING_STOP, @index) || @bytes.bytesize
            raise error(EOF_WHILE_PARSING_STRING) if @index == @bytes.bytesize

            case @bytes.getbyte(@index)
            when 0x22
              raw = @bytes.byteslice(start, @index - start).to_s
              string = scratch ? scratch << raw : raw
              eat_char
              raise error(INVALID_UNICODE_CODE_POINT) unless string.force_encoding(Encoding::UTF_8).valid_encoding?

              return string
            when 0x5c
              buffer = (scratch || +"".b) << @bytes.byteslice(start, @index - start).to_s
              eat_char
              parse_escape(buffer)
              scratch = buffer
              start = @index
            else
              eat_char
              raise error(CONTROL_CHARACTER_WHILE_PARSING_STRING)
            end
          end
        end

        # The single-character escapes and their bytes (read.rs:874-898).
        ESCAPES = {
          0x22 => "\"",
          0x5c => "\\",
          0x2f => "/",
          0x62 => "\b",
          0x66 => "\f",
          0x6e => "\n",
          0x72 => "\r",
          0x74 => "\t",
        }.freeze

        # parse_escape after a backslash (read.rs:874-898).
        private def parse_escape(scratch)
          byte = next_char
          raise error(EOF_WHILE_PARSING_STRING) unless byte
          return parse_unicode_escape(scratch) if byte == 0x75 # u

          escaped = ESCAPES[byte]
          raise error(INVALID_ESCAPE) unless escaped

          scratch << escaped
        end

        # parse_unicode_escape with validation (read.rs:900-976): a
        # surrogate must be a leading one followed by a trailing one.
        private def parse_unicode_escape(scratch)
          n1 = decode_hex_escape
          raise error(LONE_LEADING_SURROGATE_IN_HEX_ESCAPE) if n1.between?(0xDC00, 0xDFFF)
          return scratch << [n1].pack("U").b unless n1.between?(0xD800, 0xDBFF)

          [0x5c, 0x75].each do |expected| # \ u
            byte = peek
            raise error(EOF_WHILE_PARSING_STRING) unless byte

            eat_char
            raise error(UNEXPECTED_END_OF_HEX_ESCAPE) unless byte == expected
          end

          n2 = decode_hex_escape
          raise error(LONE_LEADING_SURROGATE_IN_HEX_ESCAPE) unless n2.between?(0xDC00, 0xDFFF)

          scratch << [(((n1 - 0xD800) << 10) | (n2 - 0xDC00)) + 0x10000].pack("U").b
        end

        # SliceRead#decode_hex_escape (read.rs:620-635).
        private def decode_hex_escape
          if @index + 4 > @bytes.bytesize
            @index = @bytes.bytesize
            raise error(EOF_WHILE_PARSING_STRING)
          end

          hex = @bytes.byteslice(@index, 4).to_s
          @index += 4
          raise error(INVALID_ESCAPE) unless hex.match?(/\A\h{4}\z/n)

          hex.to_i(16)
        end
      end
      private_constant :Parser

      #--
      # SPDX-SnippetEnd
      #++
    end
  end
end
