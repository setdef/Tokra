# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetCopyrightText: Erick Tryzelaar and David Tolnay (serde, serde_json)
# SPDX-SnippetCopyrightText: 2013-2025 The rust-url developers (url)
# SPDX-SnippetCopyrightText: Jacob Pratt et al. (time)
# SPDX-SnippetComment: Argument errors from tauri ipc/command.rs and error.rs;
#                      the shapes of tauri-plugin-notification src/models.rs;
#                      the messages are serde's (serde_core 1.0.228
#                      de/mod.rs, serde_derive 1.0.228 de.rs) as
#                      serde_json 1.0.140 src/value/de.rs produces them,
#                      url's for a URL (url 2.5.8 src/lib.rs:2916-2942),
#                      and time's ISO 8601 serde for a date (time 0.3.55
#                      src/serde/iso8601.rs:24-48, src/serde/visitor.rs:432-502)

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
        # This class reads the options field by field, in the order
        # serde_json's map gives them, as serde's derived visitor does,
        # through Tokra::Ipc::CommandItem, which raises
        # Tokra::Error::InvalidArgs with Tauri's <tt>invalid args `options`
        # for command `notify`: ...</tt> message and serde_json's text for
        # what was wrong. Unknown fields are ignored, and missing ones take
        # Tauri's defaults.
        #
        # === Examples
        #
        #   Arguments.new({ "options" => { "title" => "Hi" } }, "notify").notification_data.title  #=> "Hi"
        #   Arguments.new({ "options" => { "id" => 1.5 } }, "notify").notification_data
        #   # raises Tokra::Error::InvalidArgs: invalid args `options` for command `notify`:
        #   #   invalid type: floating point `1.5`, expected i32
        class Arguments
          # What serde says went wrong with one value.
          Mismatch = Tokra::Ipc::CommandItem::Mismatch

          # The variants of Schedule, in declaration order, camelCased by
          # serde (models.rs:96-124).
          SCHEDULES = %w[at interval every].freeze

          # The ISO 8601 description time's serde reads a date with:
          # time's default configuration with six-digit years
          # (serde/iso8601.rs:24-26). The configuration shapes only
          # formatting: time's parser reads every one alike
          # (parsing/parsable.rs:894-954).
          ISO8601 = Ferro::Time::FormatDescription::WellKnown::Iso8601.new(
            Ferro::Time::FormatDescription::WellKnown::Iso8601::Config::DEFAULT.set_year_is_six_digits(true)
          )

          # What time's serde visitor expects of a date
          # (serde/visitor.rs:440-442, 497-502).
          ISO8601_EXPECTING = "an ISO 8601-formatted `OffsetDateTime`"

          # The units of ScheduleEvery, read lowercased (models.rs:76-94).
          EVERY = ScheduleEvery.constants.to_h do |name|
            unit = ScheduleEvery.const_get(name, false)
            [unit.name.downcase, unit]
          end.freeze

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
            Tokra::Ipc::CommandItem.new(name: @command, key: "options", payload: @payload).deserialize do |options|
              NotificationData.new(**struct_value(options, "NotificationData", NOTIFICATION_DATA))
            end
          end

          private def mismatch(value, expected)
            raise Mismatch.invalid_type(value, expected)
          end

          # +string+ quoted as Rust's Debug quotes a str
          # (Tokra::Ipc::Unexpected.debug).
          private def debug(string)
            Tokra::Ipc::Unexpected.debug(string)
          end

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

          # An integer of +type+'s range, or serde's message
          # (Tokra::Ipc::CommandItem.integer).
          private def integer(value, type)
            Tokra::Ipc::CommandItem.integer(value, type)
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

          # A URL as url deserializes one: the Url a string parses to, or
          # url's error and the string as Rust's Debug quotes it (url 2.5.8
          # lib.rs:2916-2942, unchanged from 2.5.4).
          private def url(value)
            mismatch(value, "a string representing an URL") unless value.is_a?(String)
            Ferro::Url::Url.parse(value)
          rescue Ferro::Url::ParseError => e
            raise Mismatch, "#{e.message}: #{debug(value)}"
          end

          # A date as time's ISO 8601 visitor reads one: the
          # OffsetDateTime time parses, or time's message
          # (serde/iso8601.rs:43-48, serde/visitor.rs:445-450).
          private def date(value)
            mismatch(value, ISO8601_EXPECTING) unless value.is_a?(String)
            Ferro::Time::OffsetDateTime.parse(value, ISO8601)
          rescue Ferro::Time::Error::Parse => e
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
