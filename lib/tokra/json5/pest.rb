# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Tokra
  module Json5
    #--
    # SPDX-SnippetBegin
    # SPDX-License-Identifier: MIT OR Apache-2.0
    # SPDX-SnippetCopyrightText: 2018 Dragoș Tiselice (pest)
    # SPDX-SnippetComment: adapted from pest 2.7.15 src/error.rs:186-203
    #   (new_from_pos), :496-519 (start, spacing), :521-562 (underline),
    #   :564-605 (message, parsing_error_message, enumerate), :607-688
    #   (format, its one-position arm), :690-704 (ErrorVariant::message),
    #   :719-721 (visualize_whitespace) and src/position.rs:129-170
    #   (line_col), :189-230 (line_of, find_line_start, find_line_end)
    #++

    # How pest, the parser generator json5 is built on, words a syntax
    # error.
    #
    # json5 hands pest's error to its caller as the error's
    # <tt>to_string</tt> (json5 src/error.rs:40-52), so a Tauri developer
    # with a bad <tt>tauri.conf.json5</tt> reads pest's report: the line
    # and column, the source line, a caret under the column, and the rules
    # pest tried there. Tokra's message has to read the same, so this
    # module renders one as pest 2.7.15 does. Positions are character
    # indices into the text.
    #
    # Mirrors pest's <tt>Error::new_from_pos</tt> and its
    # <tt>Display</tt> (pest 2.7.15 src/error.rs), with
    # <tt>Position::line_col</tt> and <tt>line_of</tt> (src/position.rs).
    #
    # === Example
    #
    #   Tokra::Json5::Pest.render("{".codepoints, 1, [:identifier, :string])
    #   #=> " --> 1:2\n  |\n1 | {\n  |  ^---\n  |\n  = expected identifier or string"
    module Pest # :nodoc:
      LINE_FEED = 0x0A
      CARRIAGE_RETURN = 0x0D

      # The report pest prints for a parse that failed at +pos+ in +chars+,
      # the text's code points, having tried the rules +positives+ there,
      # listed in the order of json5's Rule enum (parser.rb's RULES).
      def self.render(chars, pos, positives)
        line, column = line_col(chars, pos)
        visualize = [LINE_FEED, CARRIAGE_RETURN].include?(chars[pos])
        text = line_of(chars, pos)
        text = visualize ? text.tr("\r\n", "␍␊") : text.delete("\r\n")
        spacing = " " * line.to_s.size
        "#{spacing}--> #{line}:#{column}\n" \
          "#{spacing} |\n" \
          "#{line} | #{text}\n" \
          "#{spacing} | #{underline(text, column)}\n" \
          "#{spacing} |\n" \
          "#{spacing} = #{message(positives)}"
      end

      # The one-based line and column of +pos+ in +chars+: a line feed
      # ends a line, and every other character, a carriage return
      # included, is a column. pest joins a carriage return and line feed
      # into one line end, which reads the same: the carriage return's
      # column is gone once the line feed starts the next line.
      def self.line_col(chars, pos)
        line = 1
        column = 1
        (chars[0, pos] || []).each do |char|
          if char == LINE_FEED
            line += 1
            column = 1
          else
            column += 1
          end
        end
        [line, column]
      end

      # The line holding +pos+, from the character after the last line
      # feed before it to the first line feed at or after it, that line
      # feed included.
      def self.line_of(chars, pos)
        start = (0...pos).reverse_each.find { |index| chars.fetch(index) == LINE_FEED }
        start = start ? start + 1 : 0
        finish = (pos...(chars.size)).find { |index| chars.fetch(index) == LINE_FEED }
        finish = finish ? finish + 1 : chars.size
        (chars[start...finish] || []).pack("U*")
      end

      # Spaces under the line up to +column+, a tab where the line has
      # one, then pest's <tt>^---</tt>.
      def self.underline(text, column)
        spaces = text.each_char.take(column - 1).map { |char| (char == "\t") ? "\t" : " " }
        "#{spaces.join}^---"
      end

      # pest's words for the rules it tried: "expected" and the rules,
      # sorted and without repeats.
      def self.message(positives)
        return "unknown parsing error" if positives.empty?

        "expected #{enumerate(positives.uniq.sort_by { |rule| Parser::RULES.index(rule) || -1 }.map(&:to_s))}"
      end

      # +names+ joined as pest joins them: one alone, two with "or", more
      # with commas and ", or" before the last.
      def self.enumerate(names)
        case names.size
        when 1 then names.fetch(0)
        when 2 then "#{names.fetch(0)} or #{names.fetch(1)}"
        else "#{names[0...-1].to_a.join(', ')}, or #{names.fetch(-1)}"
        end
      end

      #--
      # SPDX-SnippetEnd
      #++
    end
  end
end
