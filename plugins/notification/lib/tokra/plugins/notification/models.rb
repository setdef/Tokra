# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Attachment, ScheduleInterval, ScheduleEvery, Schedule,
#                      and NotificationData adapted from
#                      tauri-plugin-notification src/models.rs:11-210

module Tokra
  module Plugins
    module Notification
      # A file shown with a notification.
      #
      # A notification about a new photo reads better with the photo in it.
      # An attachment names the file by URL, with an identifier of your
      # choosing.
      #
      # Pass one to NotificationBuilder#attachment. Desktop systems ignore
      # attachments; Tauri shows them on mobile only.
      #
      # Mirrors Tauri's <tt>Attachment</tt> (models.rs:11-22). Tauri holds
      # the URL parsed; this holds the string the URL was given as.
      #
      # === Example
      #
      #   Attachment.new(id: "photo", url: "asset://localhost/photo.png")
      class Attachment < Data.define(:id, :url)
      end

      # The calendar fields a repeating notification matches.
      #
      # "Every Monday at nine" names a weekday, an hour, and a minute, and
      # leaves the rest open. ScheduleInterval holds the fields you name,
      # and +nil+ for the ones you leave open. Weekdays run from 1 (Sunday)
      # to 7 (Saturday).
      #
      # Mirrors Tauri's <tt>ScheduleInterval</tt> (models.rs:24-34).
      #
      # === Example
      #
      #   ScheduleInterval.new(weekday: 2, hour: 9, minute: 0)
      class ScheduleInterval < Data.define(:year, :month, :day, :weekday, :hour, :minute, :second)
        # Creates an interval; each field defaults to +nil+, as Tauri's
        # <tt>Default</tt> does.
        #
        # === Example
        #
        #   ScheduleInterval.new(hour: 9).minute  #=> nil
        def initialize(year: nil, month: nil, day: nil, weekday: nil, hour: nil, minute: nil, second: nil)
          super
        end
      end

      # How often a notification repeats.
      #
      # "Every two weeks" is a unit and a count. ScheduleEvery names the
      # unit; Schedule::Every pairs it with the count.
      #
      # Mirrors Tauri's <tt>ScheduleEvery</tt> (models.rs:36-94), which
      # serializes as the unit's name in camelCase.
      #
      # === Example
      #
      #   ScheduleEvery::TwoWeeks.to_s  #=> "twoWeeks"
      class ScheduleEvery < Data.define(:name)
        ##
        # Every year.
        Year = new(name: "year")
        # Every month.
        Month = new(name: "month")
        # Every two weeks.
        TwoWeeks = new(name: "twoWeeks")
        # Every week.
        Week = new(name: "week")
        # Every day.
        Day = new(name: "day")
        # Every hour.
        Hour = new(name: "hour")
        # Every minute.
        Minute = new(name: "minute")
        # Every second. Not supported on iOS.
        Second = new(name: "second")

        # The unit as Tauri displays it (models.rs:48-65).
        #
        # === Example
        #
        #   ScheduleEvery::Day.to_s  #=> "day"
        def to_s
          name
        end
      end

      # When a notification fires: at a moment, on matching calendar
      # fields, or every so often.
      #
      # Desktop systems show a notification at once and ignore its
      # schedule, as Tauri's desktop plugin does; Tauri schedules them on
      # mobile only.
      #
      # Mirrors Tauri's <tt>Schedule</tt> enum (models.rs:96-124).
      #
      # === Examples
      #
      #   Schedule::At.new(date: Time.now + 3600)
      #   Schedule::Every.new(interval: ScheduleEvery::Day, count: 1)
      module Schedule
        # At +date+, a Time, once or every year after.
        #
        # === Example
        #
        #   Schedule::At.new(date: Time.utc(2026, 12, 24, 18), repeating: true)
        class At < Data.define(:date, :repeating, :allow_while_idle)
          # Creates the schedule; +repeating+ and +allow_while_idle+
          # default to +false+, as serde's defaults do (models.rs:100-110).
          #
          # === Example
          #
          #   Schedule::At.new(date: Time.now).repeating  #=> false
          def initialize(date:, repeating: false, allow_while_idle: false)
            super
          end
        end

        # Whenever the calendar matches +interval+, a ScheduleInterval.
        #
        # === Example
        #
        #   Schedule::Interval.new(interval: ScheduleInterval.new(hour: 9, minute: 0))
        class Interval < Data.define(:interval, :allow_while_idle)
          # Creates the schedule; +allow_while_idle+ defaults to +false+
          # (models.rs:111-116).
          #
          # === Example
          #
          #   Schedule::Interval.new(interval: ScheduleInterval.new).allow_while_idle  #=> false
          def initialize(interval:, allow_while_idle: false)
            super
          end
        end

        # Every +count+ +interval+ units, a ScheduleEvery.
        #
        # === Example
        #
        #   Schedule::Every.new(interval: ScheduleEvery::Week, count: 2)
        class Every < Data.define(:interval, :count, :allow_while_idle)
          # Creates the schedule; +allow_while_idle+ defaults to +false+
          # (models.rs:117-123).
          #
          # === Example
          #
          #   Schedule::Every.new(interval: ScheduleEvery::Hour, count: 3).count  #=> 3
          def initialize(interval:, count:, allow_while_idle: false)
            super
          end
        end
      end

      # Everything a notification can carry.
      #
      # The frontend describes a notification as one object: a title, a
      # body, an icon, a schedule, and options only some systems honor.
      # NotificationData holds that object in Ruby, field by field.
      #
      # NotificationBuilder fills one in; the +notify+ command reads one
      # from the frontend. On desktop, NotificationBuilder#show uses the
      # title, body, icon, and sound, as Tauri's desktop plugin does.
      #
      # Mirrors Tauri's <tt>NotificationData</tt> (models.rs:148-210).
      #
      # === Example
      #
      #   NotificationData.new(title: "Saved", body: "Your draft is safe.")
      class NotificationData < Data.define(:id, :channel_id, :title, :body, :schedule, :large_body, :summary,
        :action_type_id, :group, :group_summary, :sound, :inbox_lines, :icon, :large_icon, :icon_color, :attachments,
        :extra, :ongoing, :auto_cancel, :silent)
        # A random identifier: any 32-bit signed integer, as Tauri's
        # <tt>rand::random</tt> picks (models.rs:181-183).
        #
        # === Example
        #
        #   NotificationData.default_id  #=> -1204578112
        def self.default_id
          Random.rand(-(2 ** 31)...(2 ** 31))
        end

        # Creates the data. Every field has Tauri's default: a random
        # +id+, +nil+ for the optional strings and the schedule, empty
        # lists and +extra+, and +false+ flags (models.rs:185-210).
        #
        # === Example
        #
        #   NotificationData.new(title: "Hi").inbox_lines  #=> []
        def initialize(id: self.class.default_id, channel_id: nil, title: nil, body: nil, schedule: nil, large_body: nil,
          summary: nil, action_type_id: nil, group: nil, group_summary: false, sound: nil, inbox_lines: [], icon: nil,
          large_icon: nil, icon_color: nil, attachments: [], extra: {}, ongoing: false, auto_cancel: false, silent: false
        )
          super
        end
      end
    end
  end
end

# SPDX-SnippetEnd
