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

  # A logger whose only target is the Webview, and the payloads its
  # log://log events carry.
  private def webview_logger(builder = Log::Builder.new)
    handle = app_handle
    payloads = []
    handle.listen("log://log") { |event| payloads << JSON.parse(event.payload) }
    logger = logger_of(builder.clear_targets.target(Log::Target.new(Log::TargetKind::Webview.new)), handle)
    [logger, payloads]
  end

  # RecordPayload { message, level } (lib.rs:317-321), where the message
  # is the formatted line (fern hands the target the formatted record).
  def test_the_event_carries_the_formatted_line_and_its_level
    logger, payloads = webview_logger(Log::Builder.new)

    logger.info("hello")

    assert_equal 1, payloads.size
    assert_match(/\A#{STAMP}\[demo\]\[INFO\] hello\z/o, payloads[0]["message"])
    assert_equal 3, payloads[0]["level"]
  end

  # LogLevel serializes each level as its number (lib.rs:70-120).
  def test_each_level_is_sent_as_its_log_level_number
    logger, payloads = webview_logger(Log::Builder.new.clear_format)

    logger.trace("t")
    logger.debug("d")
    logger.info("i")
    logger.warn("w")
    logger.error("e")
    logger.fatal("f")

    assert_equal [1, 2, 3, 4, 5, 5], payloads.map { |payload| payload["level"] }
    assert_equal %w[t d i w e f], payloads.map { |payload| payload["message"] }
  end

  # The builder's level applies to the webview as to every target.
  def test_the_level_applies_to_the_webview
    logger, payloads = webview_logger(Log::Builder.new.level(:warn))

    logger.info("dropped")

    assert_empty payloads
  end

  # A webview target with a formatter of its own formats the line again.
  def test_a_webview_target_format_applies
    handle = app_handle
    payloads = []
    handle.listen("log://log") { |event| payloads << JSON.parse(event.payload)["message"] }
    target = Log::Target.new(Log::TargetKind::Webview.new).format(Ractor.shareable_proc { |message, _| "> #{message}" })
    logger_of(Log::Builder.new.clear_format.clear_targets.target(target), handle).info("x")

    assert_equal ["> x"], payloads
  end
end
