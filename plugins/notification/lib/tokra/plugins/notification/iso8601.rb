# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: MIT OR Apache-2.0
# SPDX-SnippetCopyrightText: Jacob Pratt et al.
# SPDX-SnippetComment: The ISO 8601 parser and its errors adapted from time
#                      0.3.41: src/parsing/iso8601.rs,
#                      src/parsing/combinator/rfc/iso8601.rs,
#                      src/parsing/combinator/mod.rs, src/parsing/parsed.rs
#                      (ranges and TryFrom<Parsed>), src/parsing/parsable.rs:742-800,
#                      src/date.rs, src/offset_date_time.rs:1340-1356,
#                      src/error/*.rs, and src/serde/visitor.rs:300-355

require "date"

module Tokra
  module Plugins
    module Notification
      # Reads an ISO 8601 date and time the way Tauri's notification
      # plugin does.
      #
      # A scheduled notification names its moment as a string, and the
      # frontend sends whatever <tt>Date#toISOString</tt> or a person
      # wrote. Tauri reads it with the time crate's ISO 8601 parser and
      # rejects the invoke with that parser's words when the string is not
      # a date and time it accepts. The parser is lenient in some places
      # (basic and extended formats, ordinal and week dates, decimal
      # fractions of hours and minutes) and strict in others, and its
      # message depends on the order it tries each part.
      #
      # Iso8601.parse follows the parser step for step and returns a Time,
      # or raises Iso8601::Error with time's message.
      #
      # Mirrors time 0.3.41's <tt>OffsetDateTime::parse</tt> with
      # <tt>Iso8601::<SERDE_CONFIG></tt> (serde/iso8601.rs:24-44), which
      # Tauri's <tt>Schedule::At</tt> deserializes its date with
      # (models.rs:100-105). Years run from -9999 to 9999: time's
      # +large-dates+ feature is assumed off.
      #
      # === Examples
      #
      #   Iso8601.parse("2026-10-26T12:00:00.000Z")  #=> 2026-10-26 12:00:00 UTC
      #   Iso8601.parse("2026-13-01T00:00:00Z")
      #   # raises Iso8601::Error: unexpected trailing characters; the end of input was expected
      module Iso8601
        # A string time's parser refuses, with time's message.
        class Error < StandardError; end

        # The smallest year time accepts without +large-dates+ (date.rs:33-38).
        MIN_YEAR = -9999

        # The largest year time accepts without +large-dates+ (date.rs:39-44).
        MAX_YEAR = 9999

        # The ranges of Parsed's fields (parsed.rs:118-166).
        RANGES = {
          year: MIN_YEAR..MAX_YEAR,
          iso_year: MIN_YEAR..MAX_YEAR,
          iso_week_number: 1..53,
          ordinal: 1..366,
          day: 1..31,
          hour_24: 0..23,
          minute: 0..59,
          second: 0..60,
          subsecond: 0..999_999_999,
          offset_hour: -23..23,
          offset_minute: -59..59,
          offset_second: -59..59,
        }.freeze

        # The fields Parsed holds; +month+ and +weekday+ take any value
        # their parsers produce.
        FIELDS = (RANGES.keys + %i[month weekday]).freeze

        # The months, as the parser matches them (combinator/rfc/iso8601.rs:78-97).
        MONTHS = (1..12).to_h { |month| [format("%02d", month), month] }.freeze

        # The weekdays, Monday first, as the parser matches them
        # (combinator/rfc/iso8601.rs:109-123).
        WEEKDAYS = (1..7).to_h { |day| [day.to_s, day] }.freeze

        # time's parse error kinds (error/parse_from_description.rs:16-27).
        INVALID_LITERAL = "a character literal was not valid"
        # The message for a component that could not be parsed.
        INVALID_COMPONENT = "the '%s' component could not be parsed"
        # The message when input remains after a complete value.
        TRAILING = "unexpected trailing characters; the end of input was expected"
        # The message when the parts do not name a moment
        # (error/try_from_parsed.rs:13-19).
        INSUFFICIENT = "the `Parsed` struct did not include enough information to construct the type"

        # What the parser expected, for a value that is not a string
        # (serde/visitor.rs:300-313).
        EXPECTING = "an ISO 8601-formatted `OffsetDateTime`"

        # The parts parsed so far, as time's +Parsed+ holds them: each
        # +with+ returns a copy, or +nil+ when the value is out of range,
        # and each +set+ changes this one in place and returns +nil+ when
        # out of range (parsed.rs:575-760).
        class Parsed
          attr_reader(*FIELDS)

          # Whether a second of 60 stands for a leap second
          # (parsable.rs:756).
          attr_accessor :leap_second_allowed

          # Sets +field+ to +value+ when it is in range; +nil+ otherwise.
          def set(field, value)
            range = RANGES[field]
            return nil if range && !range.cover?(value)

            instance_variable_set(:"@#{field}", value)
            true
          end

          # A copy with +field+ set to +value+, or +nil+ when out of range.
          def with(field, value)
            copy = dup
            copy.set(field, value) && copy
          end

          # Replaces every field with +other+'s, as Rust's
          # <tt>*parsed = ...</tt> does.
          def replace(other)
            FIELDS.each { |field| instance_variable_set(:"@#{field}", other.public_send(field)) }
            self
          end
        end

        # A parse failure inside the parser, carrying time's message.
        class Failure < StandardError; end
        private_constant :Failure

        # The Time +string+ names, or Iso8601::Error with time's message.
        #
        # === Example
        #
        #   Iso8601.parse("2026-W01-1T09+01").utc  #=> 2025-12-29 08:00:00 UTC
        def self.parse(string)
          input = string.b
          parsed = Parsed.new
          rest = parse_into(input, parsed)
          raise Error, TRAILING unless rest.empty?

          offset_date_time(parsed)
        rescue Failure => e
          raise Error, e.message
        end

        # Parses a date, then a time, then an offset, remembering the first
        # failure, and fails only when none parsed (parsable.rs:742-800).
        private_class_method def self.parse_into(input, parsed)
          kind = { extended: :unknown }
          first_error = nil
          parsed.leap_second_allowed = true

          date_present = attempt(-> { parse_date(input, parsed, kind) }) { |rest| input = rest }
          first_error ||= date_present unless date_present == true
          time_present = attempt(-> { parse_time(input, parsed, kind, date_present == true) }) { |rest| input = rest }
          first_error ||= time_present unless time_present == true
          offset_present = nil
          if date_present != true || time_present == true
            offset_present = attempt(-> { parse_offset(input, parsed, kind) }) { |rest| input = rest }
            first_error ||= offset_present unless offset_present == true
          end
          raise first_error if [date_present, time_present, offset_present].none?(true)

          input
        end

        # Runs +step+, yielding its rest and answering +true+, or answers
        # its Failure.
        private_class_method def self.attempt(step)
          yield step.call
          true
        rescue Failure => e
          e
        end

        # Fails with time's message for the component +name+.
        private_class_method def self.fail_component(name)
          raise Failure, format(INVALID_COMPONENT, name)
        end

        # Fails with time's message for a missing separator.
        private_class_method def self.fail_literal
          raise Failure, INVALID_LITERAL
        end

        # [year][month][day], [year][dayo], or [year]W[week][dayk], with
        # or without separators (iso8601.rs:17-106).
        private_class_method def self.parse_date(input, parsed, kind)
          year, input = year(input) || fail_component("year")
          if input.start_with?("-")
            input = input.byteslice(1..)
            kind[:extended] = :extended
          else
            kind[:extended] = :basic
          end

          month_day = begin
            month = MONTHS[input.byteslice(0, 2)] || fail_component("month")
            rest = input.byteslice(2..)
            if kind[:extended] == :extended
              fail_literal unless rest.start_with?("-")
              rest = rest.byteslice(1..)
            end
            day, rest = digits(rest, 2, nonzero: true) || fail_component("day")
            [month, day, rest]
          rescue Failure => e
            e
          end
          unless month_day.is_a?(Failure)
            month, day, rest = month_day
            copy = parsed.with(:year, year) || fail_component("year")
            copy = copy.with(:month, month) || fail_component("month")
            copy = copy.with(:day, day) || fail_component("day")
            parsed.replace(copy)
            return rest
          end
          error = month_day

          if (ordinal, rest = digits(input, 3, nonzero: true))
            copy = parsed.with(:year, year) || fail_component("year")
            copy = copy.with(:ordinal, ordinal) || fail_component("ordinal")
            parsed.replace(copy)
            return rest
          end

          if input.start_with?("W")
            begin
              week, rest = digits(input.byteslice(1..), 2, nonzero: true) || fail_component("week")
              if kind[:extended] == :extended
                fail_literal unless rest.start_with?("-")
                rest = rest.byteslice(1..)
              end
              weekday = WEEKDAYS[rest.byteslice(0, 1)] || fail_component("weekday")
              rest = rest.byteslice(1..)
              copy = parsed.with(:iso_year, year) || fail_component("year")
              copy = copy.with(:iso_week_number, week) || fail_component("week")
              copy = copy.with(:weekday, weekday) || fail_component("weekday")
              parsed.replace(copy)
              return rest
            rescue Failure => e
              error = e
            end
          end

          raise error
        end

        # [hour][min][sec] after a T, with fractions and reduced precision
        # (iso8601.rs:108-236).
        private_class_method def self.parse_time(input, parsed, kind, date_present)
          if date_present
            fail_literal unless input.start_with?("T")
            input = input.byteslice(1..)
          end

          (hour, fraction), input = float(input) || fail_component("hour")
          if fraction
            copy = parsed.with(:hour_24, hour) || fail_component("hour")
            copy = copy.with(:minute, (fraction * 60.0).to_i) || fail_component("minute")
            copy = copy.with(:second, ((fraction * 3600.0) % 60.0).to_i) || fail_component("second")
            copy = copy.with(:subsecond, ((fraction * 3_600_000_000_000.0) % 1_000_000_000.0).to_i) ||
              fail_component("subsecond")
            parsed.replace(copy)
            return input
          end
          parsed.set(:hour_24, hour) || fail_component("hour")

          if input.start_with?(":")
            fail_component("minute") if kind[:extended] == :basic
            kind[:extended] = :extended
            input = input.byteslice(1..)
          end

          minute_parts = float(input)
          if minute_parts.nil?
            fail_component("minute") if kind[:extended] == :extended
            copy = parsed.with(:minute, 0) || fail_component("minute")
            copy = copy.with(:second, 0) || fail_component("second")
            copy = copy.with(:subsecond, 0) || fail_component("subsecond")
            parsed.replace(copy)
            return input
          end
          (minute, fraction), input = minute_parts
          kind[:extended] = :basic if kind[:extended] == :unknown
          if fraction
            copy = parsed.with(:minute, minute) || fail_component("minute")
            copy = copy.with(:second, (fraction * 60.0).to_i) || fail_component("second")
            copy = copy.with(:subsecond, ((fraction * 60_000_000_000.0) % 1_000_000_000.0).to_i) ||
              fail_component("subsecond")
            parsed.replace(copy)
            return input
          end
          parsed.set(:minute, minute) || fail_component("minute")

          if kind[:extended] == :extended
            unless input.start_with?(":")
              copy = parsed.with(:second, 0) || fail_component("second")
              copy = copy.with(:subsecond, 0) || fail_component("subsecond")
              parsed.replace(copy)
              return input
            end
            input = input.byteslice(1..)
          end

          second_parts = float(input)
          if second_parts
            (second, fraction), input = second_parts
            subsecond = fraction ? (fraction * 1_000_000_000.0).round : 0
          elsif kind[:extended] == :extended
            fail_component("second")
          else
            second = 0
            subsecond = 0
          end
          copy = parsed.with(:second, second) || fail_component("second")
          copy = copy.with(:subsecond, subsecond) || fail_component("subsecond")
          parsed.replace(copy)
          input
        end

        # Z, or a sign, an hour, and an optional minute (iso8601.rs:238-305).
        private_class_method def self.parse_offset(input, parsed, kind)
          if input.start_with?("Z")
            copy = parsed.with(:offset_hour, 0) || fail_component("offset hour")
            copy = copy.with(:offset_minute, 0) || fail_component("offset minute")
            copy = copy.with(:offset_second, 0) || fail_component("offset second")
            parsed.replace(copy)
            return input.byteslice(1..)
          end

          sign = input.byteslice(0, 1)
          fail_component("offset hour") unless ["+", "-"].include?(sign)
          hour, input = digits(input.byteslice(1..), 2) || fail_component("offset hour")
          parsed.set(:offset_hour, (sign == "-") ? -hour : hour) || fail_component("offset hour")

          if kind[:extended] != :basic && input.start_with?(":")
            kind[:extended] = :extended
            input = input.byteslice(1..)
          end

          if (minute, rest = digits(input, 2))
            input = rest
            parsed.set(:offset_minute, (sign == "-") ? -minute : minute) || fail_component("offset minute")
          else
            parsed.set(:offset_minute, 0)
          end
          kind[:extended] = :basic if kind[:extended] == :unknown
          input
        end

        # A four-digit year, or a sign and six digits
        # (combinator/rfc/iso8601.rs:63-76).
        private_class_method def self.year(input)
          sign = input.byteslice(0, 1)
          if ["+", "-"].include?(sign)
            value, rest = digits(input.byteslice(1..), 6)
            return nil unless value

            [(sign == "-") ? -value : value, rest]
          else
            digits(input, 4)
          end
        end

        # Exactly +count+ ASCII digits as an Integer and the rest; +nil+
        # when they are not there, or are zero for a +nonzero+ type
        # (combinator/mod.rs:94-110).
        private_class_method def self.digits(input, count, nonzero: false)
          text = input.byteslice(0, count)
          return nil unless text&.bytesize == count && text.match?(/\A[0-9]+\z/)

          value = Integer(text, 10)
          return nil if nonzero && value.zero?

          [value, input.byteslice(count..)]
        end

        # Two digits, then optionally a decimal sign and at least one more
        # digit: the integer and the fraction as time sums it
        # (combinator/rfc/iso8601.rs:140-177).
        private_class_method def self.float(input)
          integer, rest = digits(input, 2)
          return nil unless integer
          return [[integer, nil], rest] unless [".", ","].include?(rest.byteslice(0, 1))

          rest = rest.byteslice(1..)
          return nil unless rest.match?(/\A[0-9]/)

          fraction = (rest.getbyte(0) - 48) / 10.0
          divisor = 10.0
          rest = rest.byteslice(1..)
          while rest.match?(/\A[0-9]/)
            divisor *= 10.0
            fraction += (rest.getbyte(0) - 48) / divisor
            rest = rest.byteslice(1..)
          end
          [[integer, fraction], rest]
        end

        # The moment +parsed+ names, as <tt>TryFrom<Parsed> for
        # OffsetDateTime</tt> builds it (parsed.rs:1072-1118).
        private_class_method def self.offset_date_time(parsed)
          leap_second = parsed.leap_second_allowed && parsed.second == 60
          if leap_second
            parsed.set(:second, 59)
            parsed.set(:subsecond, 999_999_999)
          end

          year, ordinal = date(parsed)
          hour, minute, second, subsecond = time_of_day(parsed)
          raise Error, INSUFFICIENT unless parsed.offset_hour

          offset_minute = parsed.offset_minute || 0
          offset_second = parsed.offset_minute ? (parsed.offset_second || 0) : 0
          offset = (parsed.offset_hour * 3600) + (offset_minute * 60) + offset_second
          day = Date.ordinal(year, ordinal, Date::GREGORIAN)
          local = Time.new(day.year, day.month, day.day, hour, minute, Rational((second * 1_000_000_000) + subsecond, 1_000_000_000),
            offset)
          if leap_second && !leap_second_stand_in?(local)
            raise Error, "second must be in the range 0..=59 because leap seconds are not supported"
          end

          local
        end

        # The year and ordinal day of +parsed+'s date
        # (parsed.rs:850-937, date.rs:124-266).
        private_class_method def self.date(parsed)
          if parsed.year && parsed.ordinal
            from_ordinal_date(parsed.year, parsed.ordinal)
          elsif parsed.year && parsed.month && parsed.day
            from_calendar_date(parsed.year, parsed.month, parsed.day)
          elsif parsed.iso_year && parsed.iso_week_number && parsed.weekday
            from_iso_week_date(parsed.iso_year, parsed.iso_week_number, parsed.weekday)
          else
            raise Error, INSUFFICIENT
          end
        end

        # The hour, minute, second, and nanosecond of +parsed+'s time
        # (parsed.rs:939-971).
        private_class_method def self.time_of_day(parsed)
          raise Error, INSUFFICIENT unless parsed.hour_24

          case [parsed.minute, parsed.second, parsed.subsecond].map(&:nil?)
          when [true, true, true] then [parsed.hour_24, 0, 0, 0]
          when [false, true, true] then [parsed.hour_24, parsed.minute, 0, 0]
          when [false, false, true] then [parsed.hour_24, parsed.minute, parsed.second, 0]
          when [false, false, false] then [parsed.hour_24, parsed.minute, parsed.second, parsed.subsecond]
          else raise Error, INSUFFICIENT
          end
        end

        # Whether +year+ is a Gregorian leap year (time-core util.rs).
        private_class_method def self.leap_year?(year)
          (year % 4).zero? && (!(year % 100).zero? || (year % 400).zero?)
        end

        # The days in +year+: 365 or 366.
        private_class_method def self.days_in_year(year)
          leap_year?(year) ? 366 : 365
        end

        # The ISO weeks in +year+: 52 or 53 (time-core util.rs:117-132).
        private_class_method def self.weeks_in_year(year)
          Date.new(year, 12, 28, Date::GREGORIAN).cweek
        end

        # Fails with time's ComponentRange message (error/component_range.rs:60-72).
        private_class_method def self.out_of_range(name, maximum, condition)
          raise Error, "#{name} must be in the range 1..=#{maximum} #{condition}"
        end

        # The year and ordinal day, or time's range error (date.rs:173-190).
        private_class_method def self.from_ordinal_date(year, ordinal)
          out_of_range("ordinal", days_in_year(year), "for the given year") if ordinal > days_in_year(year)
          [year, ordinal]
        end

        # The year and ordinal day of a calendar date, or time's range error
        # (date.rs:124-160).
        private_class_method def self.from_calendar_date(year, month, day)
          length = Date.new(year, month, -1, Date::GREGORIAN).day
          out_of_range("day", length, "for the given month and year") if day > length
          [year, Date.new(year, month, day, Date::GREGORIAN).yday]
        end

        # The year and ordinal day of an ISO week date, or time's range error
        # (date.rs:206-266).
        private_class_method def self.from_iso_week_date(year, week, weekday)
          out_of_range("week", weeks_in_year(year), "for the given year") if week == 53 && weeks_in_year(year) < 53
          adj_year = year - 1
          raw = (365 * adj_year) + adj_year.div(4) - adj_year.div(100) + adj_year.div(400)
          jan_4 = { -6 => 8, 1 => 8, -5 => 9, 2 => 9, -4 => 10, 3 => 10, -3 => 4, 4 => 4, -2 => 5, 5 => 5, -1 => 6, 6 => 6 }
            .fetch(raw.remainder(7), 7)
          ordinal = (week * 7) + weekday - jan_4
          if ordinal <= 0
            [year - 1, ordinal + days_in_year(year - 1)]
          elsif ordinal > days_in_year(year)
            [year + 1, ordinal - days_in_year(year)]
          else
            [year, ordinal]
          end
        end

        # Whether +local+ is 23:59:59.999999999 UTC on the last day of a
        # month, the only moment a leap second may stand for
        # (offset_date_time.rs:1340-1356).
        private_class_method def self.leap_second_stand_in?(local)
          utc = local.getutc
          return false unless utc.year.between?(MIN_YEAR, MAX_YEAR)

          utc.hour == 23 && utc.min == 59 && utc.sec == 59 && utc.nsec == 999_999_999 &&
            utc.day == Date.new(utc.year, utc.month, -1, Date::GREGORIAN).day
        end
      end
    end
  end
end

# SPDX-SnippetEnd
