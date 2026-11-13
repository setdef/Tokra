# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

# The Webview target emits each formatted line as a log://log event, the
# one @tauri-apps/plugin-log's attachLogger listens for (lib.rs:642-655;
# guest-js/index.ts:243-270). A real app handle carries the event to a
# real listener.
class TestWebviewTarget < Minitest::Test
  include LogTest

  # A plugin whose only target is the Webview, and the payloads its
  # log://log events carry.
  private def webview_plugin(builder = Log::Builder.new)
    handle = app_handle
    payloads = []
    handle.listen("log://log") { |event| payloads << JSON.parse(event.payload) }
    plugin = builder.app_handle(handle).clear_targets.target(Log::Target.new(Log::TargetKind::Webview.new)).build
    [plugin, payloads]
  end

  # RecordPayload { message, level } (lib.rs:317-321), where the message
  # is the formatted line (fern hands the target the formatted record).
  def test_the_event_carries_the_formatted_line_and_its_level
    plugin, payloads = webview_plugin(Log::Builder.new.app_name("demo"))

    plugin.info("hello")

    assert_equal 1, payloads.size
    assert_match(/\A#{STAMP}\[demo\]\[INFO\] hello\z/o, payloads[0]["message"])
    assert_equal 3, payloads[0]["level"]
  end

  # LogLevel serializes each level as its number (lib.rs:70-120).
  def test_each_level_is_sent_as_its_log_level_number
    plugin, payloads = webview_plugin(Log::Builder.new.clear_format)

    plugin.trace("t")
    plugin.debug("d")
    plugin.info("i")
    plugin.warn("w")
    plugin.error("e")
    plugin.fatal("f")

    assert_equal [1, 2, 3, 4, 5, 5], payloads.map { |payload| payload["level"] }
    assert_equal %w[t d i w e f], payloads.map { |payload| payload["message"] }
  end

  # The builder's level applies to the webview as to every target.
  def test_the_level_applies_to_the_webview
    plugin, payloads = webview_plugin(Log::Builder.new.level(:warn))

    plugin.info("dropped")

    assert_empty payloads
  end

  # A webview target with a formatter of its own formats the line again.
  def test_a_webview_target_format_applies
    handle = app_handle
    payloads = []
    handle.listen("log://log") { |event| payloads << JSON.parse(event.payload)["message"] }
    target = Log::Target.new(Log::TargetKind::Webview.new).format(Ractor.shareable_proc { |message, _| "> #{message}" })
    Log::Builder.new.clear_format.app_handle(handle).clear_targets.target(target).build.info("x")

    assert_equal ["> x"], payloads
  end

  def test_the_webview_target_without_an_app_handle_raises
    error = assert_raises(ArgumentError) do
      Log::Builder.new.clear_targets.target(Log::Target.new(Log::TargetKind::Webview.new)).build
    end

    assert_equal "a Webview target needs the app handle: call Builder#app_handle", error.message
  end
end
