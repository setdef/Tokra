# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/notification_test"
require "integration/support/real_app"

# The notification plugin in a real window, called from the page through
# Tauri's own api-iife.js (plugins-workspace d4613ff0), the client
# @tauri-apps/plugin-notification builds, and through the
# window.Notification its init script defines.
#
# On Linux the page also sends, to the suite's own dunst, and the test
# reads what reached it. Elsewhere the page sends nothing, so no
# notification reaches a person's screen.
class TestNotificationWindow < RealApp::TestCase
  include NotificationTest

  FIXTURES = File.expand_path("integration/fixtures", __dir__)

  def setup
    super
    @sends = PLATFORM == :linux && Server.start.nil?
    env = @sends ? { "DBUS_SESSION_BUS_ADDRESS" => Server.address, "FIXTURE_SENDS" => "1" } : {}
    @run = self.class.fixture_run { RealApp.launch("notification", fixtures: FIXTURES, env:) }
    assert_finished @run
  end

  def test_exits_cleanly_once_every_check_passed
    assert_equal 0, @run.status, @run.describe
  end

  def test_the_page_sees_permission_granted
    assert_equal "granted", check_detail(@run, "window.Notification reports the permission granted")["permission"]
    check_detail(@run, "permission is granted on desktop")
    check_detail(@run, "mobile-only commands are not found")
  end

  def test_a_bad_option_rejects_with_tauris_message
    assert_equal "invalid args `options` for command `notify`: invalid type: floating point `1.5`, expected i32",
      check_detail(@run, "a bad option rejects with Tauri's message")["rejected"]
  end

  # Each way the page sends reaches the server with what it set
  # (desktop.rs:26-44, guest-js/init.ts:40-66).
  def test_every_way_the_page_sends_reaches_the_server
    skip "only Linux sends, to the suite's own dunst" unless @sends

    check_detail(@run, "notify, sendNotification, and new Notification send")
    notify = Server.call_with_summary("#{TITLE}: notify")
    refute_nil notify, Server.calls.inspect
    assert_equal ["from invoke", "dialog-information", "message-new-instant"],
      [notify.body, notify.app_icon, notify.hints["sound-name"]]
    assert_equal "from sendNotification", Server.call_with_summary("#{TITLE}: send")&.body
    assert_equal "from window.Notification", Server.call_with_summary("#{TITLE}: web")&.body
  end
end
