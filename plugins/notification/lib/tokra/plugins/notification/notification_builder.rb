# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: NotificationBuilder adapted from
#                      tauri-plugin-notification src/lib.rs:41-208 and its
#                      desktop show from src/desktop.rs:25-54

require "json"

module Tokra
  module Plugins
    module Notification
      # Describes one notification and shows it.
      #
      # A notification has a title and a body, and often an icon or a
      # sound. Mobile systems add more: schedules, groups, inbox lines,
      # attachments. Building all of that as one hash is easy to get
      # wrong.
      #
      # Ask Notification#builder for a builder, set what you need, and call
      # #show. Each setter returns the builder, so calls chain. On desktop,
      # #show uses the title (or the app's product name), the body, the
      # icon, and the sound, as Tauri's desktop plugin does; the other
      # fields are kept for the systems that read them.
      #
      # Mirrors Tauri's <tt>NotificationBuilder</tt> (lib.rs:41-208).
      #
      # === Example
      #
      #   handle.notification.builder
      #     .title("Download finished")
      #     .body("report.pdf is in your Downloads folder.")
      #     .sound("Ping")
      #     .show
      class NotificationBuilder
        # The NotificationData the builder fills in. The +notify+ command
        # replaces it with what the frontend sent (commands.rs:30-39).
        attr_accessor :data

        # Creates a builder for +app+, the Tokra::AppHandle whose
        # configuration #show reads. Notification#builder does this
        # (lib.rs:52-58).
        #
        # [app] the Tokra::AppHandle.
        def initialize(app)
          @app = app
          @data = NotificationData.new
        end

        # Sets the notification identifier, a 32-bit integer
        # (lib.rs:68-72).
        #
        # === Example
        #
        #   builder.id(42)
        def id(id)
          update(id:)
        end

        # Identifier of the channel that delivers this notification. If the
        # channel does not exist, the notification won't fire
        # (lib.rs:74-81).
        #
        # === Example
        #
        #   builder.channel_id("messages")
        def channel_id(id)
          update(channel_id: id)
        end

        # Sets the notification title (lib.rs:83-87).
        #
        # === Example
        #
        #   builder.title("New message")
        def title(title)
          update(title:)
        end

        # Sets the notification body (lib.rs:89-93).
        #
        # === Example
        #
        #   builder.body("You've got a new message.")
        def body(body)
          update(body:)
        end

        # Schedules this notification to fire on a later time or a fixed
        # interval (lib.rs:95-99).
        #
        # === Example
        #
        #   builder.schedule(Schedule::At.new(date: Time.now + 60))
        def schedule(schedule)
          update(schedule:)
        end

        # Multiline text. Changes the notification style to big text.
        # Cannot be used with inbox lines (lib.rs:101-107).
        #
        # === Example
        #
        #   builder.large_body("Line one\nLine two")
        def large_body(large_body)
          update(large_body:)
        end

        # Detail text for the notification with a large body, inbox lines,
        # or a group summary (lib.rs:109-113).
        #
        # === Example
        #
        #   builder.summary("3 new messages")
        def summary(summary)
          update(summary:)
        end

        # Defines an action type for this notification (lib.rs:115-119).
        #
        # === Example
        #
        #   builder.action_type_id("reply")
        def action_type_id(action_type_id)
          update(action_type_id:)
        end

        # Identifier used to group multiple notifications (lib.rs:121-127).
        #
        # === Example
        #
        #   builder.group("chat")
        def group(group)
          update(group:)
        end

        # Instructs the system that this notification is the summary of a
        # group on Android (lib.rs:129-133).
        #
        # === Example
        #
        #   builder.group_summary
        def group_summary
          update(group_summary: true)
        end

        # The sound resource name for the notification (lib.rs:135-139):
        # a system sound such as <tt>"Ping"</tt> on macOS, a sound theme
        # name such as <tt>"message-new-instant"</tt> on Linux.
        #
        # === Example
        #
        #   builder.sound("Ping")
        def sound(sound)
          update(sound:)
        end

        # Appends an inbox line to the notification. Changes the
        # notification style to inbox. Cannot be used with a large body.
        # Only supports up to 5 lines (lib.rs:141-149).
        #
        # === Example
        #
        #   builder.inbox_line("Ada: lunch?").inbox_line("Grace: sure")
        def inbox_line(line)
          update(inbox_lines: [*@data.inbox_lines, line])
        end

        # Notification icon (lib.rs:151-157): an icon name or a path. On
        # Android the icon must be placed in the app's
        # <tt>res/drawable</tt> folder.
        #
        # === Example
        #
        #   builder.icon("dialog-information")
        def icon(icon)
          update(icon:)
        end

        # Notification large icon, on Android (lib.rs:159-165).
        #
        # === Example
        #
        #   builder.large_icon("ic_large")
        def large_icon(large_icon)
          update(large_icon:)
        end

        # Icon color on Android (lib.rs:167-171).
        #
        # === Example
        #
        #   builder.icon_color("#336699")
        def icon_color(icon_color)
          update(icon_color:)
        end

        # Appends an attachment to the notification (lib.rs:173-177).
        #
        # === Example
        #
        #   url = Ferro::Url::Url.parse("asset://localhost/photo.png")
        #   builder.attachment(Attachment.new(id: "photo", url:))
        def attachment(attachment)
          update(attachments: [*@data.attachments, attachment])
        end

        # Adds an extra payload to store in the notification: +value+ as
        # JSON reads it back, as Tauri's <tt>serde_json::to_value</tt>
        # stores it (lib.rs:179-185): keys become strings, and NaN and
        # Infinity become +nil+, as serde_json stores a non-finite float.
        #
        # === Example
        #
        #   builder.extra("conversation", 7)
        def extra(key, value)
          update(extra: @data.extra.merge(key.to_s => JSON.parse(JSON.generate([finite(value)])).first))
        end

        # If set, the notification cannot be dismissed by the user on
        # Android. An application service must manage the dismissal of the
        # notification (lib.rs:187-195).
        #
        # === Example
        #
        #   builder.ongoing
        def ongoing
          update(ongoing: true)
        end

        # Automatically cancels the notification when the user clicks on
        # it (lib.rs:197-201).
        #
        # === Example
        #
        #   builder.auto_cancel
        def auto_cancel
          update(auto_cancel: true)
        end

        # Changes the notification presentation to be silent on iOS: no
        # badge, no sound, not listed (lib.rs:203-207).
        #
        # === Example
        #
        #   builder.silent
        def silent
          update(silent: true)
        end

        # Shows the notification and returns +nil+.
        #
        # The title is the one you set, or the app's product name. The
        # body, icon, and sound go along when set; without an icon, the
        # notification takes the program's own. The notification goes out
        # on a thread of its own, so #show never waits for the
        # notification server or the notification center, and a failure
        # there is dropped, as in Tauri.
        #
        # Each call starts a thread of its own, however many are already
        # sending; Tauri's sends share tokio's pool instead. When the app
        # exits, Ruby waits for a send still under way: on macOS up to
        # about two seconds, while the notification center confirms
        # delivery, and on Linux only until the interrupt ends the D-Bus
        # call.
        #
        # On macOS the first notification names the app it comes from, by
        # the app's identifier, once for the whole process; see Plugin.
        #
        # Mirrors Tauri's desktop <tt>NotificationBuilder::show</tt>
        # (desktop.rs:25-54).
        #
        # === Example
        #
        #   handle.notification.builder.title("Done").show
        def show
          desktop_notification.show
          nil
        end

        # The desktop notification #show sends: the app's identifier, the
        # title or the product name, and the body, icon, and sound when
        # set (desktop.rs:26-44).
        private def desktop_notification
          config = @app.config
          notification = Imp::Notification.new(config.identifier || "")
          title = @data.title || config.product_name
          notification = notification.title(title) if title
          notification = notification.body(@data.body) if @data.body
          notification = notification.icon(@data.icon) if @data.icon
          notification = notification.sound(@data.sound) if @data.sound
          notification
        end

        # +value+ with every NaN and Infinity inside it replaced by +nil+,
        # as <tt>serde_json::to_value</tt> turns them into null.
        private def finite(value)
          case value
          when Float then value.finite? ? value : nil
          when Array then value.map { |item| finite(item) }
          when Hash then value.transform_values { |item| finite(item) }
          else value
          end
        end

        # Replaces fields of #data and returns the builder.
        private def update(**fields)
          @data = @data.with(**fields)
          self
        end
      end
    end
  end
end

# SPDX-SnippetEnd
