# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/notification_test"

# Linux, end to end: the plugin's commands send real notifications to a
# real server, dunst, on a session bus of the suite's own, and
# dbus-monitor records the Notify call that reached it
# (NotificationTest::Server). The send runs on its own thread, so each
# test waits for the call to arrive.
class TestLinuxNotifications < Minitest::Test
  include NotificationTest

  def setup
    skip_unless_platform(:linux)
    require_server
  end

  # notify sends the title as the summary, with the body, icon, and the
  # sound as the sound-name hint (desktop.rs:26-44, 180-194).
  def test_notify_sends_the_title_body_icon_and_sound
    options = {
"title" => "#{TITLE}: command",
"body" => "Build finished",
"icon" => "dialog-information",
"sound" => "message-new-instant",
"largeBody" => "only mobile reads this",
}
    assert_equal [true, nil], answer("notify", { "options" => options })

    call = Server.call_with_summary("#{TITLE}: command")
    refute_nil call, "dunst never got the notification: #{Server.calls.inspect}"
    assert_equal ["Build finished", "dialog-information"], [call.body, call.app_icon]
    assert_equal "message-new-instant", call.hints["sound-name"]
  end

  # Without a title the product name stands in (desktop.rs:29-35), and
  # without an icon notify-rust names the program's own (desktop.rs:187-191).
  def test_the_product_name_and_the_programs_icon_stand_in
    handle = configured_handle(identifier: "app.tokra.test", product_name: "#{TITLE}: product")
    Notification::Notification.new(handle).builder.body("from Ruby").show

    call = Server.call_with_summary("#{TITLE}: product")
    refute_nil call, "dunst never got the notification: #{Server.calls.inspect}"
    assert_equal "from Ruby", call.body
    assert_equal Ferro::NotifyRust::Notification.new.auto_icon.icon, call.app_icon
    refute call.hints.key?("sound-name")
  end

  # A server that is gone does not reach the frontend: the send's error
  # is dropped and the command still resolves, as in Tauri
  # (desktop.rs:216-218).
  def test_a_failed_send_is_dropped
    address = ENV.fetch("DBUS_SESSION_BUS_ADDRESS")
    ENV["DBUS_SESSION_BUS_ADDRESS"] = "unix:path=#{Dir.tmpdir}/tokra-notification-no-bus"
    thread = Notification::Imp::Notification.new("").title("#{TITLE}: nowhere").show
    assert_nil thread.join(10).value
    assert_equal [true, nil], answer("notify", { "options" => { "title" => "#{TITLE}: nowhere" } })
  ensure
    ENV["DBUS_SESSION_BUS_ADDRESS"] = address if address
  end
end
