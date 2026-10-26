# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetCopyrightText: Erick Tryzelaar and David Tolnay (serde, serde_json)
# SPDX-SnippetComment: Argument errors from tauri ipc/command.rs and error.rs;
#                      the shapes of tauri-plugin-notification src/models.rs;
#                      the messages are serde's (serde_core 1.0.228
#                      de/mod.rs, serde_derive 1.0.228 de.rs) as
#                      serde_json 1.0.140 src/value/de.rs produces them

require "json"

module Tokra
  module Plugins
    module Notification
      module Commands
        # Reads the +notify+ command's options the way Tauri deserializes
        # them.
        #
        # Tauri's +notify+ takes a typed <tt>NotificationData</tt>, and
        # serde turns the frontend's JSON into it or rejects the invoke
        # with a precise message: a wrong type, a number out of range, an
        # unknown schedule, a date or URL its parser refuses. The
        # frontend's error handling, and a developer reading the console,
        # depend on those words.
        #
        # This class reads the options field by field, in the order the
        # object gives them, as serde's derived visitor does, and raises
        # ArgumentError with Tauri's <tt>invalid args `options` for
        # command `notify`: ...</tt> message (tauri error.rs:59-60) and
        # serde_json's text for what was wrong. Unknown fields are
        # ignored, and missing ones take Tauri's defaults.
        #
        # === Examples
        #
        #   Arguments.new({ "options" => { "title" => "Hi" } }, "notify").notification_data.title  #=> "Hi"
        #   Arguments.new({ "options" => { "id" => 1.5 } }, "notify").notification_data
        #   # raises ArgumentError: invalid args `options` for command `notify`:
        #   #   invalid type: floating point `1.5`, expected i32
        class Arguments
          # What serde says went wrong with one value.
          class Mismatch < StandardError; end

          # The variants of Schedule, in declaration order, camelCased by
          # serde (models.rs:96-124).
          SCHEDULES = %w[at interval every].freeze

          # The units of ScheduleEvery, read lowercased (models.rs:76-94).
          EVERY = ScheduleEvery.constants.to_h do |name|
            unit = ScheduleEvery.const_get(name, false)
            [unit.name.downcase, unit]
          end.freeze

          # The integer ranges serde checks (serde_core de/impls.rs).
          RANGES = { "i32" => -(2 ** 31)...(2 ** 31), "u8" => 0..255 }.freeze

          # The range of integers serde_json reads as integers; others it
          # reads as floats (serde_json de.rs, parse_integer).
          JSON_INTEGERS = -(2 ** 63)...(2 ** 64)

          # Fields of a derived struct: the wire name, the Ruby name, the
          # default (+:required+, +:option+ for an <tt>Option</tt> without
          # a default, or a value or Proc), and the reader.
          NOTIFICATION_DATA = [
            ["id", :id, -> { NotificationData.default_id }, :i32],
            ["channelId", :channel_id, :option, :optional_string],
            ["title", :title, :option, :optional_string],
            ["body", :body, :option, :optional_string],
            ["schedule", :schedule, :option, :optional_schedule],
            ["largeBody", :large_body, :option, :optional_string],
            ["summary", :summary, :option, :optional_string],
            ["actionTypeId", :action_type_id, :option, :optional_string],
            ["group", :group, :option, :optional_string],
            ["groupSummary", :group_summary, false, :bool],
            ["sound", :sound, :option, :optional_string],
            ["inboxLines", :inbox_lines, -> { [] }, :strings],
            ["icon", :icon, :option, :optional_string],
            ["largeIcon", :large_icon, :option, :optional_string],
            ["iconColor", :icon_color, :option, :optional_string],
            ["attachments", :attachments, -> { [] }, :attachments],
            ["extra", :extra, -> { {} }, :map],
            ["ongoing", :ongoing, false, :bool],
            ["autoCancel", :auto_cancel, false, :bool],
            ["silent", :silent, false, :bool],
          ].freeze

          # Attachment's fields (models.rs:11-16).
          ATTACHMENT = [["id", :id, :required, :string], ["url", :url, :required, :url]].freeze

          # ScheduleInterval's fields (models.rs:24-34).
          SCHEDULE_INTERVAL = %w[year month day weekday hour minute second].map do |name|
            [name, name.to_sym, :option, :optional_u8]
          end.freeze

          # Schedule::At's fields (models.rs:100-110).
          AT = [
            ["date", :date, :required, :date],
            ["repeating", :repeating, false, :bool],
            ["allowWhileIdle", :allow_while_idle, false, :bool],
          ].freeze

          # Schedule::Interval's fields (models.rs:111-116).
          INTERVAL = [
            ["interval", :interval, :required, :schedule_interval],
            ["allowWhileIdle", :allow_while_idle, false, :bool],
          ].freeze

          # Schedule::Every's fields (models.rs:117-123).
          EVERY_FIELDS = [
            ["interval", :interval, :required, :every],
            ["count", :count, :required, :u8],
            ["allowWhileIdle", :allow_while_idle, false, :bool],
          ].freeze

          # Creates a reader for +payload+, the invoke's arguments, of
          # +command+.
          #
          # [payload] the invoke's payload Hash.
          # [command] the command name, for the messages.
          def initialize(payload, command)
            @payload = payload || {}
            @command = command
          end

          # The required +options+ as NotificationData (commands.rs:30-35).
          #
          # === Example
          #
          #   args.notification_data.body  #=> "You've got mail."
          def notification_data
            argument("options") do
              NotificationData.new(**struct_value(required("options"), "NotificationData", NOTIFICATION_DATA))
            end
          end

          # Runs the block, turning a Mismatch into Tauri's InvalidArgs
          # message for +key+.
          private def argument(key)
            yield
          rescue Mismatch => e
            raise ArgumentError, "invalid args `#{key}` for command `#{@command}`: #{e.message}"
          end

          # A required argument, or Tauri's missing-key message
          # (tauri ipc/command.rs:97-102).
          private def required(key)
            return @payload[key] if @payload.key?(key)

            raise Mismatch, "command #{@command} missing required key #{key}"
          end

          private def mismatch(value, expected)
            raise Mismatch, "invalid type: #{unexpected(value)}, expected #{expected}"
          end

          # serde_json's description of a JSON value (value/de.rs:1395-1404,
          # serde de/mod.rs Unexpected).
          private def unexpected(value)
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

          # A float as serde_json shows one, through ryu: the shortest
          # digits, as a decimal from 1e-5 to below 1e16 and with an
          # exponent otherwise, written <tt>1e16</tt> and <tt>1.5e-7</tt>
          # (serde_json error.rs JsonUnexpected, ryu 1.0 pretty/mod.rs
          # format64).
          private def float_text(float)
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

          #--
          # SPDX-SnippetEnd
          #++

          # The shortest digits of positive +float+ and where its decimal
          # point falls: the value is 0.DIGITS times ten to that power.
          private def shortest_digits(float)
            mantissa, exponent = float.to_s.split("e")
            whole, fraction = mantissa.split(".")
            digits = "#{whole}#{fraction}"
            point = whole.length + exponent.to_i
            stripped = digits.sub(/\A0+/, "")
            point -= digits.length - stripped.length
            [stripped.sub(/0+\z/, ""), point]
          end

          #--
          # SPDX-SnippetBegin
          # SPDX-License-Identifier: MIT OR Apache-2.0
          # SPDX-SnippetCopyrightText: The Rust Project Developers
          # SPDX-SnippetComment: debug follows the rules of Rust's str Debug,
          #   char::escape_debug_ext and core/src/unicode/printable.py
          #++

          # Characters Rust's Debug escapes as <tt>\u{..}</tt>: grapheme
          # extenders, and what it does not print: controls, format
          # characters, surrogates, private use, unassigned code points,
          # and every separator but the space.
          UNPRINTABLE = /\p{Grapheme_Extend}|[\p{Cc}\p{Cf}\p{Cs}\p{Co}\p{Cn}\p{Zl}\p{Zp}[\p{Zs}&&[^ ]]]/

          # +string+ quoted as Rust's Debug quotes a str: escapes for
          # quotes, backslashes, tabs, returns, newlines, and NUL, and
          # <tt>\u{..}</tt> for UNPRINTABLE characters (char::escape_debug).
          # Ruby's Unicode tables stand in for Rust's, which may be a
          # version apart.
          private def debug(string)
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
          # SPDX-SnippetBegin
          # SPDX-License-Identifier: Apache-2.0 OR MIT
          # SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
          # SPDX-SnippetCopyrightText: Erick Tryzelaar and David Tolnay (serde, serde_json)
          # SPDX-SnippetComment: the rest of Arguments, as above
          #++

          private def string(value)
            value.is_a?(String) ? value : mismatch(value, "a string")
          end

          private def optional_string(value)
            value.nil? ? nil : string(value)
          end

          private def bool(value)
            [true, false].include?(value) ? value : mismatch(value, "a boolean")
          end

          private def i32(value)
            integer(value, "i32")
          end

          private def u8(value)
            integer(value, "u8")
          end

          private def optional_u8(value)
            value.nil? ? nil : u8(value)
          end

          # An integer of +type+'s range, or serde's message: a value out
          # of range is invalid, anything else the wrong type
          # (serde_core de/impls.rs, primitive visitors).
          private def integer(value, type)
            mismatch(value, type) unless value.is_a?(Integer) && JSON_INTEGERS.cover?(value)
            raise Mismatch, "invalid value: integer `#{value}`, expected #{type}" unless RANGES.fetch(type).cover?(value)

            value
          end

          private def strings(value)
            sequence(value) { |item| string(item) }
          end

          private def sequence(value, &)
            mismatch(value, "a sequence") unless value.is_a?(Array)
            value.map(&)
          end

          # A <tt>HashMap<String, Value></tt>: any object.
          private def map(value)
            value.is_a?(Hash) ? value : mismatch(value, "a map")
          end

          private def attachments(value)
            sequence(value) { |item| Attachment.new(**struct_value(item, "Attachment", ATTACHMENT)) }
          end

          # A URL as url 2.5.4 deserializes one: a string Url::parse takes,
          # or its error and the string (url lib.rs:2886-2911).
          private def url(value)
            mismatch(value, "a string representing an URL") unless value.is_a?(String)
            UrlCheck.check(value)
          rescue UrlCheck::Error => e
            raise Mismatch, "#{e.message}: #{debug(value)}"
          end

          # A date as time 0.3.41's ISO 8601 visitor reads one
          # (serde/visitor.rs:300-313).
          private def date(value)
            mismatch(value, Iso8601::EXPECTING) unless value.is_a?(String)
            Iso8601.parse(value)
          rescue Iso8601::Error => e
            raise Mismatch, e.message
          end

          private def schedule_interval(value)
            ScheduleInterval.new(**struct_value(value, "ScheduleInterval", SCHEDULE_INTERVAL))
          end

          # A ScheduleEvery: any string naming a unit, ignoring case
          # (models.rs:76-94).
          private def every(value)
            text = string(value)
            EVERY.fetch(text.downcase) { raise Mismatch, "unknown every kind '#{text}'" }
          end

          private def optional_schedule(value)
            value.nil? ? nil : schedule(value)
          end

          # An externally tagged Schedule: an object with the variant's
          # name as its one key and the variant's fields as its value
          # (serde_json value/de.rs:322-341, 763-797, 592-612).
          private def schedule(value)
            case value
            when String then variant = value
            when Hash
              raise Mismatch, "invalid value: map, expected map with a single key" unless value.size == 1

              variant, content = value.first
              present = true
            else mismatch(value, "string or map")
            end
            raise Mismatch, "unknown variant `#{variant}`, expected #{one_of(SCHEDULES)}" unless SCHEDULES.include?(variant)
            raise Mismatch, "invalid type: unit variant, expected struct variant" unless present
            mismatch(content, "struct variant") unless content.is_a?(Hash)

            case variant
            when "at" then Schedule::At.new(**struct_value(content, "struct variant Schedule::At", AT))
            when "interval" then Schedule::Interval.new(**struct_value(content, "struct variant Schedule::Interval", INTERVAL))
            else Schedule::Every.new(**struct_value(content, "struct variant Schedule::Every", EVERY_FIELDS))
            end
          end

          # serde's OneOf list of variant names (de/mod.rs:2339-2352).
          private def one_of(variants)
            "one of #{variants.map { |name| "`#{name}`" }.join(', ')}"
          end

          # The fields of a derived struct named +name+ as a Hash of Ruby
          # names to values. An object is read key by key in sorted order,
          # skipping unknown keys, then each missing field takes its
          # default; an array is read field by field
          # (serde_derive de.rs:450-560, 763-860).
          private def struct_value(value, name, fields)
            expecting = name.start_with?("struct variant") ? name : "struct #{name}"
            case value
            when Hash then struct_from_map(value, fields)
            when Array then struct_from_sequence(value, expecting, fields)
            else mismatch(value, expecting)
            end
          end

          # serde_json's Map, without its +preserve_order+ feature, as
          # Tauri builds it, is a BTreeMap: serde visits the keys in byte
          # order, whatever order the frontend sent them in.
          private def struct_from_map(value, fields)
            read = {}
            value.sort_by { |key, _| key.b }.each do |key, item|
              _, ruby, _, reader = fields.find { |field| field.first == key }
              read[ruby] = __send__(reader, item) if ruby
            end
            fields.to_h do |wire, ruby, default, _|
              next [ruby, read[ruby]] if read.key?(ruby)
              raise Mismatch, "missing field `#{wire}`" if default == :required

              [ruby, default_value(default)]
            end
          end

          private def struct_from_sequence(value, expecting, fields)
            count = fields.length
            expecting = "#{expecting} with #{count} element#{'s' unless count == 1}"
            values = fields.each_with_index.to_h do |(_, ruby, default, reader), index|
              next [ruby, __send__(reader, value[index])] if index < value.length
              raise Mismatch, "invalid length #{index}, expected #{expecting}" if %i[required option].include?(default)

              [ruby, default_value(default)]
            end
            raise Mismatch, "invalid length #{value.length}, expected fewer elements in array" if value.length > count

            values
          end

          private def default_value(default)
            case default
            when :option then nil
            when Proc then default.call
            else default
            end
          end
        end
      end
    end
  end
end

# SPDX-SnippetEnd
