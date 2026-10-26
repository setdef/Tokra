# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/notification_test"

# Windows toasts. Whether a CI runner's session shows toasts is unknown,
# so the send's result is not checked; Tauri drops it too
# (desktop.rs:216-218).
class TestWindowsNotifications < Minitest::Test
  include NotificationTest

  def setup
    skip_unless_platform(:windows)
  end

  # Tauri names the app only when it runs installed (desktop.rs:195-206);
  # no installer registers a Tokra app, so the toast names none and
  # comes from PowerShell (plan 024, decision 5).
  #
  # notify-rust keeps the field crate-private and ferro-notify-rust binds
  # only its setter, so the test reads notify-rust's Debug text, where the
  # field appears (notify-rust 4.18.2 src/notification.rs:49, 91-92).
  def test_a_toast_names_no_app
    handle = configured_handle(identifier: "app.tokra.windows-test")
    builder = Notification::Notification.new(handle).builder.title(TITLE)
    debug = builder.__send__(:desktop_notification).to_notify_rust.inspect
    assert_includes debug, "app_id: None"
    assert_includes Ferro::NotifyRust::Notification.new.app_id("x").inspect, 'app_id: Some("x")'
  end

  def test_notify_resolves_and_its_send_ends
    assert_equal [true, nil], answer("notify", { "options" => { "title" => TITLE, "body" => "Windows" } })
    thread = Notification::Imp::Notification.new("").title(TITLE).show
    assert_nil thread.join(30).value
  end
end
