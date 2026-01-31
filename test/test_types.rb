# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra public types: Response, Invoke, UriSchemeContext, etc.
#
# These tests document the expected API for application developers and
# are designed to be mutation-resistant.
class TestTypes < Minitest::Test
  # --- Response ---

  def test_response_stores_status_headers_body
    response = Tokra::Response.new(status: 200, headers: { "x-foo" => "bar" }, body: "OK")

    assert_equal 200, response.status
    assert_equal({ "x-foo" => "bar" }, response.headers)
    assert_equal "OK", response.body
  end

  def test_response_ok_factory_creates_200_with_html_content_type
    response = Tokra::Response.ok("<h1>Hello</h1>")

    assert_equal 200, response.status
    assert_equal "text/html", response.headers["content-type"]
    assert_equal "<h1>Hello</h1>", response.body
  end

  def test_response_ok_factory_accepts_custom_content_type
    response = Tokra::Response.ok('{"ok":true}', content_type: "application/json")

    assert_equal 200, response.status
    assert_equal "application/json", response.headers["content-type"]
  end

  def test_response_not_found_factory_creates_404
    response = Tokra::Response.not_found

    assert_equal 404, response.status
    assert_equal "text/plain", response.headers["content-type"]
    assert_equal "Not Found", response.body
  end

  def test_response_not_found_factory_accepts_custom_message
    response = Tokra::Response.not_found("Page missing")

    assert_equal 404, response.status
    assert_equal "Page missing", response.body
  end

  def test_response_error_factory_creates_custom_status
    response = Tokra::Response.error(500, "Internal error")

    assert_equal 500, response.status
    assert_equal "text/plain", response.headers["content-type"]
    assert_equal "Internal error", response.body
  end

  # --- Invoke ---

  def test_invoke_stores_command_and_payload
    invoke = Tokra::Invoke.new(command: "greet", payload: '{"name":"World"}', responder: nil)

    assert_equal "greet", invoke.command
    assert_equal '{"name":"World"}', invoke.payload
  end

  def test_invoke_resolve_calls_responder_with_success
    calls = []
    responder = -> (success, value) { calls << [success, value] }

    invoke = Tokra::Invoke.new(command: "cmd", payload: "", responder:)
    invoke.resolve("result")

    assert_equal [[true, "result"]], calls
  end

  def test_invoke_reject_calls_responder_with_failure
    calls = []
    responder = -> (success, value) { calls << [success, value] }

    invoke = Tokra::Invoke.new(command: "cmd", payload: "", responder:)
    invoke.reject("error message")

    assert_equal [[false, "error message"]], calls
  end

  def test_invoke_only_responds_once
    calls = []
    responder = -> (success, value) { calls << [success, value] }

    invoke = Tokra::Invoke.new(command: "cmd", payload: "", responder:)
    invoke.resolve("first")
    invoke.resolve("second")
    invoke.reject("third")

    assert_equal 1, calls.size, "Should only call responder once"
    assert_equal [[true, "first"]], calls
  end

  def test_invoke_without_responder_does_not_error
    invoke = Tokra::Invoke.new(command: "cmd", payload: "", responder: nil)

    # Should not raise
    invoke.resolve("value")
    invoke.reject("error")
  end

  # --- UriSchemeContext ---

  def test_uri_scheme_context_stores_app_handle_and_label
    handle = Tokra::AppHandle.new({})
    ctx = Tokra::UriSchemeContext.new(app_handle: handle, webview_label: "main")

    assert_same handle, ctx.app_handle
    assert_equal "main", ctx.webview_label
  end

  # --- PageLoadPayload ---

  def test_page_load_payload_stores_url_and_started
    payload = Tokra::PageLoadPayload.new(url: "tokra://localhost/", started: true)

    assert_equal "tokra://localhost/", payload.url
    assert payload.started?
    refute payload.finished?
  end

  def test_page_load_payload_finished_is_inverse_of_started
    payload = Tokra::PageLoadPayload.new(url: "tokra://localhost/about", started: false)

    refute payload.started?
    assert payload.finished?
  end

  # --- WindowEvent variants ---

  def test_window_event_close_requested_exists
    event = Tokra::WindowEvent::CloseRequested.new
    assert_instance_of Tokra::WindowEvent::CloseRequested, event
  end

  def test_window_event_destroyed_exists
    event = Tokra::WindowEvent::Destroyed.new
    assert_instance_of Tokra::WindowEvent::Destroyed, event
  end

  def test_window_event_focused_stores_value
    event = Tokra::WindowEvent::Focused.new(focused: true)
    assert event.focused
  end

  def test_window_event_moved_stores_coordinates
    event = Tokra::WindowEvent::Moved.new(x: 100, y: 200)
    assert_equal 100, event.x
    assert_equal 200, event.y
  end

  def test_window_event_resized_stores_dimensions
    event = Tokra::WindowEvent::Resized.new(width: 800, height: 600)
    assert_equal 800, event.width
    assert_equal 600, event.height
  end

  # --- RunEvent variants ---

  def test_run_event_ready_is_data_value
    event = Tokra::RunEvent::Ready.new
    assert_instance_of Tokra::RunEvent::Ready, event
  end

  def test_run_event_exit_is_data_value
    event = Tokra::RunEvent::Exit.new
    assert_instance_of Tokra::RunEvent::Exit, event
  end

  def test_run_event_exit_requested_stores_code
    event = Tokra::RunEvent::ExitRequested.new(code: 42)
    assert_equal 42, event.code
  end
end
