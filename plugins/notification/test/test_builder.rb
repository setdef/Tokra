# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/notification_test"

# NotificationBuilder's setters (lib.rs:41-208) and what its desktop show
# hands notify-rust (desktop.rs:25-54, 179-194), read back through
# ferro-notify-rust's real Notification without sending anything.
class TestBuilder < Minitest::Test
  include NotificationTest

  def test_each_setter_fills_in_notification_data
    attachment = Notification::Attachment.new(id: "a", url: Ferro::Url::Url.parse("file:///a.png"))
    schedule = Notification::Schedule::Every.new(interval: Notification::ScheduleEvery::Day, count: 1)
    builder = builder_for(configured_handle)
    returned = builder.id(5).channel_id("c").title("t").body("b").schedule(schedule).large_body("lb").summary("s")
      .action_type_id("a").group("g").group_summary.sound("Ping").inbox_line("one").inbox_line("two").icon("i")
      .large_icon("li").icon_color("#000").attachment(attachment).extra("k", { list: [1, :two] }).ongoing
      .auto_cancel.silent

    assert_same builder, returned
    assert_equal Notification::NotificationData.new(
      id: 5, channel_id: "c", title: "t", body: "b", schedule:, large_body: "lb", summary: "s", action_type_id: "a",
      group: "g", group_summary: true, sound: "Ping", inbox_lines: ["one", "two"], icon: "i", large_icon: "li",
      icon_color: "#000", attachments: [attachment], extra: { "k" => { "list" => [1, "two"] } }, ongoing: true,
      auto_cancel: true, silent: true
    ), builder.data
  end

  # Tauri's url field is a url::Url (models.rs:11-16), so a string there
  # is a type error, not a URL to check later.
  def test_an_attachment_refuses_a_url_that_is_not_parsed
    error = assert_raises(TypeError) { Notification::Attachment.new(id: "a", url: "file:///a.png") }
    assert_equal "wrong argument type String (expected Ferro::Url::Url)", error.message
  end

  def test_a_schedule_refuses_a_date_that_is_not_parsed
    error = assert_raises(TypeError) { Notification::Schedule::At.new(date: Time.utc(2026, 10, 26, 12)) }
    assert_equal "wrong argument type Time (expected Ferro::Time::OffsetDateTime)", error.message
  end

  # serde_json::to_value stores NaN and Infinity as null (lib.rs:179-185).
  def test_extra_stores_non_finite_floats_as_null
    builder = builder_for(configured_handle).extra("nan", Float::NAN).extra(:list, [Float::INFINITY, 1.5])
    assert_equal({ "nan" => nil, "list" => [nil, 1.5] }, builder.data.extra)
  end

  # A new builder starts from NotificationData's defaults (lib.rs:52-58,
  # models.rs:185-210): a random 32-bit id and nothing else set.
  def test_a_new_builder_starts_from_the_defaults
    data = builder_for(configured_handle).data
    assert_includes(-(2 ** 31)...(2 ** 31), data.id)
    assert_nil data.title
    refute data.silent
  end

  # The desktop show sends the title as notify-rust's summary, with the
  # body, icon, and sound (desktop.rs:26-44, 180-194).
  def test_show_hands_notify_rust_the_title_body_icon_and_sound
    builder = builder_for(configured_handle(identifier: "com.example.app", product_name: "Example"))
      .title("Saved").body("Your draft is safe.").icon("document-save").sound("Ping").large_body("ignored")
    notification = desktop(builder).to_notify_rust

    assert_equal "Saved", notification.summary
    assert_equal "Your draft is safe.", notification.body
    assert_equal "document-save", notification.icon
    assert_includes notification.inspect, '"Ping"'
    refute_includes notification.inspect, "ignored"
    assert_equal "com.example.app", desktop(builder).identifier
  end

  # Without a title, the product name stands in (desktop.rs:29-35).
  def test_without_a_title_the_product_name_is_the_summary
    named = desktop(builder_for(configured_handle(product_name: "Example")).body("b")).to_notify_rust
    assert_equal "Example", named.summary

    unnamed = desktop(builder_for(configured_handle).body("b")).to_notify_rust
    assert_equal "", unnamed.summary
  end

  # Without an icon, notify-rust takes the program's own (desktop.rs:187-191):
  # its executable's name, which for Tokra is Ruby's.
  def test_without_an_icon_notify_rust_picks_the_programs_own
    expected = Ferro::NotifyRust::Notification.new.auto_icon.icon
    refute_empty expected
    assert_equal expected, desktop(builder_for(configured_handle).title("t")).to_notify_rust.icon
  end

  # Tauri names its app by identifier (desktop.rs:115-121); Tokra has no
  # config file to set one yet, so it is empty.
  def test_the_identifier_is_empty_without_one
    assert_equal "", desktop(builder_for(configured_handle)).identifier
  end

  private def builder_for(handle)
    Notification::Notification.new(handle).builder
  end

  private def desktop(builder)
    builder.__send__(:desktop_notification)
  end
end
