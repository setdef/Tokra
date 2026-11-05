# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Tokra
  module Json5
    #--
    # SPDX-SnippetBegin
    # SPDX-License-Identifier: ISC AND (MIT OR Apache-2.0)
    # SPDX-SnippetCopyrightText: 2018 Callum Oakley (json5)
    # SPDX-SnippetCopyrightText: 2018 Dragoș Tiselice (pest)
    # SPDX-SnippetComment: the grammar of json5 0.4.1 src/json5.pest and its
    #   Seq and Map access (src/de.rs:401-472), ISC; run as pest_derive
    #   2.7.15 generates it (pest_generator src/generator.rs:205-415: the
    #   Rule order, the rule calls, atomicity, and skip), with the attempt
    #   tracking of pest 2.7.15 src/parser_state.rs:457-498 (state),
    #   :609-733 (rule), and :784-824 (track), MIT OR Apache-2.0
    #++

    # One parse of a JSON5 text, as json5's pest grammar parses it.
    #
    # json5's grammar (src/json5.pest) is a PEG that pest compiles into
    # functions, one per rule. Each named rule records where it failed,
    # and pest reports the furthest place a named rule failed with every
    # rule that failed there; that is where Tauri's message points and
    # what it says it expected. This class runs the same rules in the same
    # order over the text's code points, keeps the same record, and builds
    # the value as json5's deserializer would from the parse.
    #
    # Arrays and objects nest without limit in json5. Tokra keeps them on
    # its own stack of Frame objects rather than Ruby's, so a deep config
    # does not raise SystemStackError where Tauri reads it. Strings and
    # numbers, which do not nest, are plain methods.
    #
    # Of pest's machinery, only what json5's grammar reaches is here:
    # positive attempts (no rule of json5's runs under a negative
    # lookahead), no call limit, and no atomic rule that calls a named
    # one. No named rule of json5's can fail with a named child failing
    # where it started: every child starts past an opening quote or
    # bracket, or, for an identifier's first char_literal, cannot fail
    # once its lookahead passed. So pest's truncation of a rule's
    # children and its keeping of a lone child (parser_state.rs:796-807)
    # never act, and are left out. A failed rule leaves the position where
    # it started, as every failing sequence in pest restores it.
    #
    # Mirrors the parser json5 0.4.1 derives with pest_derive 2.7.15
    # (src/de.rs:12-14), and pest's <tt>ParserState</tt>.
    class Parser # :nodoc:
      # json5's Rule enum in its declared order, EOI first, as
      # pest_generator declares it and as pest sorts the rules it reports
      # (generator.rs:205-260, parser_state.rs:474-477).
      RULES = %i[
        EOI
        COMMENT
        WHITESPACE
        array
        boolean
        char_escape_sequence
        char_literal
        decimal_integer_literal
        decimal_literal
        double_quote_char
        escape_char
        escape_sequence
        exponent_part
        hex_escape_sequence
        hex_integer_literal
        identifier
        identifier_part
        identifier_start
        key
        line_continuation
        line_terminator
        line_terminator_sequence
        non_escape_char
        nul_escape_sequence
        null
        number
        numeric_literal
        object
        pair
        single_escape_char
        single_quote_char
        string
        text
        unicode_escape_sequence
        unicode_letter
        value
      ].freeze

      # Characters the grammar names.
      BACKSLASH = 0x5C
      DOUBLE_QUOTE = 0x22
      SINGLE_QUOTE = 0x27
      DOLLAR = 0x24
      UNDERSCORE = 0x5F
      ZWNJ = 0x200C
      ZWJ = 0x200D

      # line_terminator: LF, CR, LINE SEPARATOR, PARAGRAPH SEPARATOR.
      LINE_TERMINATORS = [0x0A, 0x0D, 0x2028, 0x2029].freeze

      # WHITESPACE's own characters, besides SPACE_SEPARATOR and the line
      # terminators: tab, vertical tab, form feed, space, no-break space,
      # and the byte order mark.
      WHITESPACE = [0x09, 0x0B, 0x0C, 0x20, 0xA0, 0xFEFF].freeze

      # The characters json5 escapes with a letter, and the quotes and
      # backslash (single_escape_char).
      SINGLE_ESCAPES = "'\"\\bfnrtv".codepoints.freeze

      # pest's Unicode classes. pest 2.7.15 reads Unicode 16.0's tables and
      # Ruby 4.0 reads 17.0's, so each class admits only a character
      # assigned by 16.0 (Age=16.0 holds every character assigned in
      # 16.0 or before).
      SPACE_SEPARATOR = /\A(?=\p{Age=16.0})\p{Zs}\z/
      UNICODE_LETTER = /\A(?=\p{Age=16.0})[\p{Lu}\p{Ll}\p{Lt}\p{Lm}\p{Lo}\p{Nl}]\z/
      IDENTIFIER_PART = /\A(?=\p{Age=16.0})(?:\p{Mn}|\p{Diacritic}|\p{Nd}|\p{Pc})\z/

      # An array or object being parsed, and the value whose alternatives
      # are being tried: what Ruby's stack would hold for each nested call
      # of a recursive parser.
      class Frame # :nodoc:
        # :value, :object, or :array.
        attr_reader :rule
        # Where the rule started.
        attr_reader :start
        # The members parsed so far.
        attr_reader :elements, :entries
        # Which step comes next: :start, :first, :next (and for a value,
        # :object or :array, the alternative being tried).
        attr_accessor :state
        # Where a repetition's failed iteration goes back to.
        attr_accessor :restore
        # The key of the entry whose value is being parsed, and its error.
        attr_accessor :key, :key_error
        # The first error a member left for the deserializer.
        attr_accessor :error

        def initialize(rule, start)
          @rule = rule
          @start = start
          @elements = [] #: Array[json_value]
          @entries = {} #: Hash[String, json_value]
          @state = :start
          @restore = start
          @key = ""
          @key_error = nil
          @error = nil
        end

        # Adds +value+, and keeps the first error, the key's before the
        # value's, as serde reads a key before its value.
        def add(value, error)
          if rule == :object
            entries[key] = value
            self.error ||= key_error
          else
            elements << value
          end
          self.error ||= error
        end

        # The parsed value: an object's entries in byte order, as
        # serde_json's map keeps them.
        def value
          (rule == :object) ? entries.sort.to_h : elements
        end
      end

      def initialize(text)
        @chars = text.codepoints
        @pos = 0
        @attempt_pos = 0
        @pos_attempts = [] #: Array[Symbol]
      end

      # Parses the whole text and answers its value, raising Error with
      # pest's report for a syntax error, or the deserializer's first error
      # in the text's order once it parses.
      #
      # text = _{ SOI ~ value ~ EOI }
      def parse
        skip
        ok, value, error = parse_value
        if ok
          skip
          ok = rule(:EOI) { @pos == @chars.size }
        end
        unless ok
          line, column = Pest.line_col(@chars, @attempt_pos)
          raise Error.new(Pest.render(@chars, @attempt_pos, @pos_attempts), Location.new(line:, column:))
        end
        raise deferred(error) if error

        value
      end

      # The error a leaf left, with its location.
      private def deferred(error)
        message, pos = error
        line, column = Pest.line_col(@chars, pos)
        Error.new(message, Location.new(line:, column:))
      end

      # --- pest's ParserState ---

      # Runs the block as the named rule +name+: answers whether it
      # matched, and when it did not, records the failure as pest does and
      # goes back to where it started (parser_state.rs:609-733).
      private def rule(name)
        start = @pos
        return true if yield

        failed(name, start)
        false
      end

      # A named rule that started at +start+ failed.
      private def failed(name, start)
        @pos = start
        track(name, start)
      end

      # pest's record of a failed rule: kept only at the furthest position
      # any rule failed, with every rule that failed there
      # (parser_state.rs:784-824).
      private def track(name, pos)
        if pos > @attempt_pos
          @pos_attempts.clear
          @attempt_pos = pos
        end
        @pos_attempts << name if pos == @attempt_pos
      end

      # A Frame for +name+ starting here.
      private def frame(name)
        Frame.new(name, @pos)
      end

      # The text's code point at the position, or +nil+ at its end.
      private def char
        @chars[@pos]
      end

      # Matches +string+ here and moves past it, or answers +false+.
      private def match(string)
        codepoints = string.codepoints
        return false unless @chars[@pos, codepoints.size] == codepoints

        @pos += codepoints.size
        true
      end

      # --- the grammar's values ---

      # value = _{ null | boolean | string | number | object | array },
      # with every array and object on the Frame stack. Answers whether a
      # value matched, the value, and the first error its leaves left.
      private def parse_value
        stack = [frame(:value)]
        returned = nil #: [bool, json_value, [String, Integer]?]?
        until stack.empty?
          current = stack.fetch(-1)
          step = (current.rule == :value) ? step_value(current, returned) : step_collection(current, returned)
          if step.is_a?(Frame)
            stack << step
            returned = nil
          else
            stack.pop
            returned = step
          end
        end
        returned || [false, nil, nil]
      end

      # The next step of a value: the leaves in the grammar's order, then
      # an object, then an array.
      private def step_value(current, returned)
        case current.state
        when :start
          leaf = parse_leaf
          return leaf if leaf

          current.state = :object
          frame(:object)
        when :object
          return returned if returned&.fetch(0)

          current.state = :array
          frame(:array)
        else
          returned || [false, nil, nil]
        end
      end

      # null, boolean, string, or number here, as a finished value, or
      # +nil+ when none matched.
      private def parse_leaf
        start = @pos
        return [true, nil, nil] if rule(:null) { match("null") }
        return [true, @chars[start] == 0x74, nil] if rule(:boolean) { match("true") || match("false") }

        string = parse_string
        return [true, string.fetch(0), string.fetch(1)] if string

        number = parse_number
        return [true, number.fetch(0), number.fetch(1)] if number

        nil
      end

      # The next step of an array or object:
      #
      #   array = { "[" ~ "]" | "[" ~ value ~ ("," ~ value)* ~ ","? ~ "]" }
      #   object = { "{" ~ "}" | "{" ~ pair ~ ("," ~ pair)* ~ ","? ~ "}" }
      #   pair = _{ key ~ ":" ~ value }
      #
      # with pest's skip of whitespace and comments between the parts.
      private def step_collection(current, returned)
        open, close = (current.rule == :object) ? ["{", "}"] : ["[", "]"]
        case current.state
        when :start
          return collection_failed(current) unless match(open)

          skip
          return [true, current.value, nil] if match(close)
          return collection_failed(current) unless member_head(current)

          current.state = :first
          frame(:value)
        else
          ok, value, error = returned || [false, nil, nil]
          unless ok
            return collection_failed(current) if current.state == :first

            @pos = current.restore
            return collection_tail(current, close)
          end
          current.add(value, error)
          collection_next(current, close)
        end
      end

      # After a member: the next "," and member, or the end.
      private def collection_next(current, close)
        current.restore = @pos
        skip
        if match(",")
          skip
          if member_head(current)
            current.state = :next
            return frame(:value)
          end
        end
        @pos = current.restore
        collection_tail(current, close)
      end

      # What comes before a member's value: an object's key and colon.
      private def member_head(current)
        return true unless current.rule == :object

        key = parse_key
        return false unless key

        skip
        return false unless match(":")

        skip
        current.key, current.key_error = key
        true
      end

      # ","? ~ "]" (or "}") after the last member.
      private def collection_tail(current, close)
        skip
        match(",")
        skip
        return [true, current.value, current.error] if match(close)

        collection_failed(current)
      end

      private def collection_failed(current)
        failed(current.rule, current.start)
        [false, nil, nil]
      end

      # key = _{ identifier | string }
      private def parse_key
        parse_identifier || parse_string
      end

      # --- strings ---

      # string = ${ "\"" ~ double_quote_char* ~ "\"" | "'" ~ single_quote_char* ~ "'" }
      #
      # Answers the string and the error converting it left, or +nil+.
      private def parse_string
        start = @pos
        components = [] #: Array[[Symbol, String]]
        return nil unless rule(:string) { quoted(DOUBLE_QUOTE, components) || quoted(SINGLE_QUOTE, components) }

        convert(start) { De.string(components) }
      end

      # One quoted string's alternative, with +quote+ its quote.
      private def quoted(quote, components)
        start = @pos
        size = components.size
        if char == quote
          @pos += 1
          nil while quote_char(quote, components)
          if char == quote
            @pos += 1
            return true
          end
        end
        @pos = start
        components.pop(components.size - size)
        false
      end

      # double_quote_char (or single_quote_char) =
      #   _{ "\\" ~ escape_sequence | line_continuation | !quote ~ char_literal }
      private def quote_char(quote, components)
        start = @pos
        if char == BACKSLASH
          @pos += 1
          return true if escape_sequence(components) || line_terminator_sequence

          @pos = start
        end
        return false if char == quote

        char_literal(components)
      end

      # escape_sequence = _{
      #   char_escape_sequence | nul_escape_sequence |
      #   "x" ~ hex_escape_sequence | "u" ~ unicode_escape_sequence }
      private def escape_sequence(components)
        return true if rule(:char_escape_sequence) { component(:char_escape_sequence, components) if char_escape? }
        return true if rule(:nul_escape_sequence) { component(:nul_escape_sequence, components) if char == 0x30 }

        hex_escape(0x78, :hex_escape_sequence, 2, components) ||
          hex_escape(0x75, :unicode_escape_sequence, 4, components)
      end

      # +letter+ ~ the rule +name+ of +digits+ hexadecimal digits.
      private def hex_escape(letter, name, digits, components)
        start = @pos
        return false unless char == letter

        @pos += 1
        return true if rule(name) { hex_digits?(digits) && component(name, components, digits) }

        @pos = start
        false
      end

      # char_escape_sequence = @{ single_escape_char | non_escape_char },
      # where non_escape_char = _{ !(escape_char | line_terminator) ~ ANY }
      # and escape_char = _{ single_escape_char | ASCII_DIGIT | "x" | "u" }.
      private def char_escape?
        code = char
        return false unless code
        return true if SINGLE_ESCAPES.include?(code)

        !(code.between?(0x30, 0x39) || code == 0x78 || code == 0x75 || LINE_TERMINATORS.include?(code))
      end

      # line_continuation's line_terminator_sequence =
      #   _{ "\u{000D}" ~ "\u{000A}" | line_terminator }
      private def line_terminator_sequence
        return true if match("\r\n")
        return false unless line_terminator?(char)

        @pos += 1
        true
      end

      # char_literal = @{ !("\\" | line_terminator) ~ ANY }
      private def char_literal(components)
        rule(:char_literal) do
          code = char
          component(:char_literal, components) if code && code != BACKSLASH && !LINE_TERMINATORS.include?(code)
        end
      end

      # Records the +length+ characters here as a component of rule +name+
      # and moves past them.
      private def component(name, components, length = 1)
        components << [name, (@chars[@pos, length] || []).pack("U*")]
        @pos += length
        true
      end

      # Whether +count+ ASCII hexadecimal digits come next.
      private def hex_digits?(count)
        (0...count).all? { |offset| hex?(@chars[@pos + offset]) }
      end

      private def hex?(code)
        !code.nil? && (code.between?(0x30, 0x39) || code.between?(0x41, 0x46) || code.between?(0x61, 0x66))
      end

      # --- identifiers ---

      # identifier = ${ identifier_start ~ identifier_part* }
      private def parse_identifier
        start = @pos
        components = [] #: Array[[Symbol, String]]
        matched = rule(:identifier) do
          next false unless identifier_start(components)

          nil while identifier_part(components)
          true
        end
        return nil unless matched

        convert(start) { De.string(components) }
      end

      # identifier_start = _{
      #   &(unicode_letter | "$" | "_") ~ char_literal | "\\u" ~ unicode_escape_sequence }
      private def identifier_start(components)
        code = char
        return true if code && (code == DOLLAR || code == UNDERSCORE || unicode?(code, UNICODE_LETTER)) &&
          char_literal(components)

        return false unless code == BACKSLASH

        start = @pos
        @pos += 1
        return true if hex_escape(0x75, :unicode_escape_sequence, 4, components)

        @pos = start
        false
      end

      # identifier_part = _{
      #   identifier_start | &(NONSPACING_MARK | DIACRITIC | DECIMAL_NUMBER |
      #   CONNECTOR_PUNCTUATION | "\u{200C}" | "\u{200D}") ~ char_literal }
      private def identifier_part(components)
        return true if identifier_start(components)

        code = char
        !code.nil? && (code == ZWNJ || code == ZWJ || unicode?(code, IDENTIFIER_PART)) && char_literal(components)
      end

      # Whether the character +code+ is in the class +pattern+.
      private def unicode?(code, pattern)
        code.chr(Encoding::UTF_8).match?(pattern)
      end

      # --- numbers ---

      # number = @{ ("+" | "-")? ~ numeric_literal }
      #
      # Answers the number and the error converting it left, or +nil+.
      private def parse_number
        start = @pos
        matched = rule(:number) do
          finish = number_end(@pos)
          @pos = finish if finish
          !finish.nil?
        end
        return nil unless matched

        text = (@chars[start...@pos] || []).pack("U*")
        convert(start) { De.number(text) }
      end

      # Where a number starting at +pos+ ends, or +nil+.
      private def number_end(pos)
        pos += 1 if [0x2B, 0x2D].include?(@chars[pos])
        hex_integer_end(pos) || decimal_end(pos) || word_end(pos, "Infinity") || word_end(pos, "NaN")
      end

      # hex_integer_literal = _{ ^"0x" ~ ASCII_HEX_DIGIT+ }
      private def hex_integer_end(pos)
        return nil unless @chars[pos] == 0x30 && [0x58, 0x78].include?(@chars[pos + 1]) && hex?(@chars[pos + 2])

        pos += 2
        pos += 1 while hex?(@chars[pos])
        pos
      end

      # decimal_literal = _{
      #   decimal_integer_literal ~ "." ~ ASCII_DIGIT* ~ exponent_part? |
      #   "." ~ ASCII_DIGIT+ ~ exponent_part? |
      #   decimal_integer_literal ~ exponent_part? }
      private def decimal_end(pos)
        integer = integer_end(pos)
        if integer && @chars[integer] == 0x2E
          fraction = digits_end(integer + 1)
          return exponent_end(fraction) || fraction
        end
        if @chars[pos] == 0x2E && digit?(@chars[pos + 1])
          fraction = digits_end(pos + 1)
          return exponent_end(fraction) || fraction
        end
        return nil unless integer

        exponent_end(integer) || integer
      end

      # decimal_integer_literal = _{ "0" | ASCII_NONZERO_DIGIT ~ ASCII_DIGIT* }
      private def integer_end(pos)
        code = @chars[pos]
        return pos + 1 if code == 0x30
        return nil unless code && code.between?(0x31, 0x39)

        digits_end(pos + 1)
      end

      # exponent_part = _{ ^"e" ~ ("+" | "-")? ~ ASCII_DIGIT+ }
      private def exponent_end(pos)
        return nil unless [0x45, 0x65].include?(@chars[pos])

        pos += 1
        pos += 1 if [0x2B, 0x2D].include?(@chars[pos])
        digit?(@chars[pos]) ? digits_end(pos) : nil
      end

      private def digits_end(pos)
        pos += 1 while digit?(@chars[pos])
        pos
      end

      private def digit?(code)
        !code.nil? && code.between?(0x30, 0x39)
      end

      private def word_end(pos, word)
        codepoints = word.codepoints
        (@chars[pos, codepoints.size] == codepoints) ? pos + codepoints.size : nil
      end

      # --- whitespace and comments ---

      # pest's implicit skip between the parts of a non-atomic rule:
      # WHITESPACE* ~ (COMMENT ~ WHITESPACE*)* (generator.rs:394-413).
      private def skip
        loop do
          @pos += 1 while whitespace?(char)
          break unless comment
        end
      end

      # WHITESPACE = _{ "\u{0009}" | "\u{000B}" | "\u{000C}" | "\u{0020}" |
      #   "\u{00A0}" | "\u{FEFF}" | SPACE_SEPARATOR | line_terminator }
      private def whitespace?(code)
        return false unless code

        WHITESPACE.include?(code) || LINE_TERMINATORS.include?(code) || unicode?(code, SPACE_SEPARATOR)
      end

      # COMMENT = _{ "/*" ~ (!"*/" ~ ANY)* ~ "*/" | "//" ~ (!line_terminator ~ ANY)* }
      private def comment
        start = @pos
        if match("/*")
          until @pos >= @chars.size
            return true if match("*/")

            @pos += 1
          end
          @pos = start
          return false
        end
        return false unless match("//")

        @pos += 1 until @pos >= @chars.size || line_terminator?(char)
        true
      end

      # line_terminator = _{ "\u{000A}" | "\u{000D}" | "\u{2028}" | "\u{2029}" }
      private def line_terminator?(code)
        !code.nil? && LINE_TERMINATORS.include?(code)
      end

      # Runs the deserializer's conversion of the leaf at +start+, keeping
      # its error for later: json5 converts only once the whole text has
      # parsed, so a syntax error anywhere comes first.
      private def convert(start)
        [yield, nil]
      rescue Error => e
        [nil, [e.message, start]]
      end

      #--
      # SPDX-SnippetEnd
      #++
    end
  end
end
