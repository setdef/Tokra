# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/notification_test"

# macOS, in child processes only.
#
# notify-rust names the app a notification comes from by replacing what
# the process reports as its bundle identifier, once per process
# (mac-notification-sys 0.6.15 objc/notify.h:20-46, src/lib.rs:131-158),
# so each test that names the app runs in a child of its own.
#
# The tests that only name the app send nothing; they read NSBundle's
# answer back. The test that sends first claims Finder for the child: a
# notification from a process the notification center does not know as
# Finder is never confirmed delivered here, and mac-notification-sys gives
# up after two seconds (objc/notify.m:160-180), as ferro-notify-rust's own
# tests rely on. A sweeper removes any test notification a Mac does show.
# The plugin's own naming then finds the app already set and, as Tauri
# does, ignores that.
class TestMacosNotifications < Minitest::Test
  include NotificationTest

  def setup
    skip_unless_platform(:macos)
  end

  # Tokra serves its pages through its own protocol, as Tauri's release
  # builds do, so the app is named by its identifier (desktop.rs:207-214).
  def test_the_app_is_named_by_its_identifier
    named, = in_child(<<~RUBY)
      #{BUNDLE_IDENTIFIER}
      Tokra::Plugins::Notification::Imp::Notification.new("com.apple.finder").name_application
      bundle_identifier
    RUBY

    assert_equal "com.apple.finder", named
  end

  # An identifier no installed app has, as for an app run from source,
  # leaves notify-rust sending as Terminal, which is what Tauri's
  # development builds name; the error is ignored, as Tauri's let _ does.
  def test_an_unknown_identifier_sends_as_terminal
    named, errors = in_child(<<~RUBY)
      #{BUNDLE_IDENTIFIER}
      Tokra::Plugins::Notification::Imp::Notification.new("app.tokra.no-such-app").name_application
      bundle_identifier
    RUBY

    assert_equal "com.apple.Terminal", named
    assert_empty errors
  end

  # The first app named wins for the whole process; the plugin's later
  # naming is ignored.
  def test_an_app_named_first_keeps_its_name
    named, = in_child(<<~RUBY)
      #{BUNDLE_IDENTIFIER}
      Ferro::NotifyRust.set_application("com.apple.finder")
      Tokra::Plugins::Notification::Imp::Notification.new("app.tokra.no-such-app").name_application
      bundle_identifier
    RUBY

    assert_equal "com.apple.finder", named
  end

  # The command settles while the send still waits for the notification
  # center, on a thread of its own (desktop.rs:216-218), and the send ends
  # without raising.
  def test_notify_resolves_while_the_send_waits
    outcome, errors = in_child(<<~RUBY)
      #{SWEEPER}
      Ferro::NotifyRust.set_application("com.apple.finder")
      app = Tokra::Builder.default.build(native: StubNative)
      handle = app.handle
      plugin = Tokra::Plugins::Notification::Plugin.new(handle)
      handle.plugin(plugin)
      window = Tokra::Window.new(label: "main", native: Object.new, app_handle: handle)
      webview = Tokra::Webview.new(label: "main", native: Object.new, window:, app_handle: handle)
      answers = Thread::Queue.new
      invoke = Tokra::Ipc::Invoke.new(command: "notify", payload: { "options" => { "title" => #{TITLE.dump}, "body" => "sent" } },
        webview:, responder: ->(success, json) { answers << [success, JSON.parse(json)] })
      before = Thread.list
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      plugin.extend_api(invoke)
      answer = answers.pop(timeout: 1)
      answered = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      senders = Thread.list - before
      sending = senders.map(&:alive?)
      senders.each { |thread| thread.join(10) }
      [answer, answered, sending, senders.map(&:value)]
    RUBY

    answer, answered, sending, values = outcome
    assert_equal [true, nil], answer
    assert_operator answered, :<, 0.5
    assert_equal [true], sending, "one thread should still be sending when the command answered"
    assert_equal [nil], values
    assert_empty errors
  end
end
