# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/autorun"
require "minitest/mock"
require "tokra-log"

# Tests for Webview target kind (Tauri parity).
#
# TargetKind::Webview emits log events to WebView via AppHandle#emit.
# Frontend subscribes via attachConsole() to display in browser console.
class TestLogTargetKindWebview < Minitest::Test
  def test_webview_is_data_class_with_no_fields
    webview = Tokra::Plugins::Log::TargetKind::Webview.new

    assert_kind_of Data, webview
    assert_equal [], webview.members
  end

  def test_to_logger_creates_webview_logger
    target = Tokra::Plugins::Log::Target.new(Tokra::Plugins::Log::TargetKind::Webview.new)
    stub_app_handle = Minitest::Mock.new
    builder = Tokra::Plugins::Log::Builder.new
      .app_handle(stub_app_handle)

    logger = target.to_logger(builder)

    assert_kind_of Tokra::Plugins::Log::WebviewLogger, logger
  end

  # WebviewLogger emits "log://log" events with RecordPayload.
  # Level mapping: Ruby Logger severity → Tauri LogLevel
  #   TRACE=-1→1, DEBUG=0→2, INFO=1→3, WARN=2→4, ERROR=3→5, FATAL=4→5
  def test_trace_emits_with_tauri_level_1
    emitted = []
    stub_handle = Object.new
    stub_handle.define_singleton_method(:emit) { |event, payload| emitted << [event, payload] }

    logger = Tokra::Plugins::Log::WebviewLogger.new(stub_handle)
    logger.trace("trace message")

    assert_equal 1, emitted.size
    assert_equal "log://log", emitted[0][0]
    assert_equal({ message: "trace message", level: 1 }, emitted[0][1])
  end
end
