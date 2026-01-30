# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::Native event types
#
# These tests verify the Rust-defined event classes that are passed to Ruby
# callbacks during the event loop. These tests can run headlessly since the
# event objects don't require windowing—they're just data containers.
#
# Note: The native extension creates these objects internally and passes them
# to Ruby. We test them to ensure the Ruby-facing API is stable and correct.
class TestNativeEvents < Minitest::Test
  # ==========================================================================
  # IpcEvent Tests
  # ==========================================================================

  def test_ipc_event_is_defined
    assert defined?(Tokra::Native::IpcEvent), "IpcEvent should be defined"
  end

  def test_ipc_event_new_accepts_message
    event = Tokra::Native::IpcEvent.new("hello from JS")

    assert_kind_of Tokra::Native::IpcEvent, event
  end

  def test_ipc_event_message_returns_stored_string
    event = Tokra::Native::IpcEvent.new("test message")

    assert_equal "test message", event.message
  end

  def test_ipc_event_message_preserves_unicode
    event = Tokra::Native::IpcEvent.new("こんにちは 🎌")

    assert_equal "こんにちは 🎌", event.message
  end

  def test_ipc_event_message_preserves_empty_string
    event = Tokra::Native::IpcEvent.new("")

    assert_equal "", event.message
  end

  # ==========================================================================
  # WakeUpEvent Tests
  # ==========================================================================

  def test_wake_up_event_is_defined
    assert defined?(Tokra::Native::WakeUpEvent), "WakeUpEvent should be defined"
  end

  def test_wake_up_event_new_accepts_payload
    event = Tokra::Native::WakeUpEvent.new("worker response")

    assert_kind_of Tokra::Native::WakeUpEvent, event
  end

  def test_wake_up_event_payload_returns_stored_string
    event = Tokra::Native::WakeUpEvent.new("response data")

    assert_equal "response data", event.payload
  end

  def test_wake_up_event_payload_preserves_json
    json_payload = '{"status":"ok","data":[1,2,3]}'
    event = Tokra::Native::WakeUpEvent.new(json_payload)

    assert_equal json_payload, event.payload
  end

  # ==========================================================================
  # WindowCloseEvent Tests
  # ==========================================================================

  def test_window_close_event_is_defined
    assert defined?(Tokra::Native::WindowCloseEvent), "WindowCloseEvent should be defined"
  end

  def test_window_close_event_new_requires_no_arguments
    event = Tokra::Native::WindowCloseEvent.new

    assert_kind_of Tokra::Native::WindowCloseEvent, event
  end

  # ==========================================================================
  # HttpRequestEvent Tests
  # ==========================================================================

  def test_http_request_event_is_defined
    assert defined?(Tokra::Native::HttpRequestEvent), "HttpRequestEvent should be defined"
  end

  def test_http_request_event_new_accepts_all_fields
    event = Tokra::Native::HttpRequestEvent.new(
      123,
      "POST",
      "tokra://localhost/api",
      [["Content-Type", "application/json"]],
      '{"key":"value"}'
    )

    assert_kind_of Tokra::Native::HttpRequestEvent, event
  end

  def test_http_request_event_request_id_returns_integer
    event = Tokra::Native::HttpRequestEvent.new(42, "GET", "tokra://localhost/", [], "")

    assert_equal 42, event.request_id
  end

  def test_http_request_event_method_returns_http_verb
    event = Tokra::Native::HttpRequestEvent.new(1, "DELETE", "tokra://localhost/resource", [], "")

    assert_equal "DELETE", event.method
  end

  def test_http_request_event_uri_returns_full_uri
    event = Tokra::Native::HttpRequestEvent.new(1, "GET", "tokra://localhost/path?query=1", [], "")

    assert_equal "tokra://localhost/path?query=1", event.uri
  end

  def test_http_request_event_body_returns_request_body
    event = Tokra::Native::HttpRequestEvent.new(1, "POST", "tokra://localhost/", [], "form=data")

    assert_equal "form=data", event.body
  end

  def test_http_request_event_body_requires_utf8
    binary = "\x00\x01\x02\xFF".b

    # Rust extension enforces UTF-8 for string parameters
    assert_raises(EncodingError) do
      Tokra::Native::HttpRequestEvent.new(1, "POST", "tokra://localhost/", [], binary)
    end
  end

  # ==========================================================================
  # PageLoadEvent Tests
  # ==========================================================================

  def test_page_load_event_is_defined
    assert defined?(Tokra::Native::PageLoadEvent), "PageLoadEvent should be defined"
  end

  def test_page_load_event_new_accepts_event_and_url
    event = Tokra::Native::PageLoadEvent.new("started", "https://example.com/")

    assert_kind_of Tokra::Native::PageLoadEvent, event
  end

  def test_page_load_event_event_returns_started_or_finished
    started = Tokra::Native::PageLoadEvent.new("started", "https://example.com/")
    finished = Tokra::Native::PageLoadEvent.new("finished", "https://example.com/")

    assert_equal "started", started.event
    assert_equal "finished", finished.event
  end

  def test_page_load_event_url_returns_page_url
    event = Tokra::Native::PageLoadEvent.new("started", "https://example.com/page")

    assert_equal "https://example.com/page", event.url
  end

  def test_page_load_event_started_predicate_returns_true_when_started
    event = Tokra::Native::PageLoadEvent.new("started", "https://example.com/")

    assert event.started?, "#started? should return true for 'started' event"
  end

  def test_page_load_event_started_predicate_returns_false_when_finished
    event = Tokra::Native::PageLoadEvent.new("finished", "https://example.com/")

    refute event.started?, "#started? should return false for 'finished' event"
  end

  def test_page_load_event_finished_predicate_returns_true_when_finished
    event = Tokra::Native::PageLoadEvent.new("finished", "https://example.com/")

    assert event.finished?, "#finished? should return true for 'finished' event"
  end

  def test_page_load_event_finished_predicate_returns_false_when_started
    event = Tokra::Native::PageLoadEvent.new("started", "https://example.com/")

    refute event.finished?, "#finished? should return false for 'started' event"
  end

  # Mutation testing: ensure predicates are checking the right value
  def test_page_load_event_predicates_are_mutually_exclusive
    started = Tokra::Native::PageLoadEvent.new("started", "https://example.com/")
    finished = Tokra::Native::PageLoadEvent.new("finished", "https://example.com/")

    refute_equal started.started?, started.finished?,
      "started? and finished? should be mutually exclusive for 'started'"
    refute_equal finished.started?, finished.finished?,
      "started? and finished? should be mutually exclusive for 'finished'"
  end
end
