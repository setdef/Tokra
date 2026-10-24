# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/stub_native"

# Tests for Builder#app: serving a Rack app over the tokra:// protocol
# through the unified App path (ADR 004 porcelain over Rack::Handler).
class TestBuilderRackApp < Minitest::Test
  # A minimal Rack app echoing the path it received.
  ECHO_APP = -> (env) { [200, { "content-type" => "text/plain" }, ["echo:#{env['PATH_INFO']}"]] }

  def test_app_rejects_non_rack_objects
    error = assert_raises(Tokra::Error) { Tokra::Builder.new.app(Object.new) }
    assert_match(/respond to #call/, error.message)
  end

  def test_title_and_size_configure_the_window
    app = Tokra::Builder.new.title("Configured").size(1024, 768).build(native: StubNative)

    assert_equal "Configured", app.config[:title]
    assert_in_delta 1024.0, app.config[:width]
    assert_in_delta 768.0, app.config[:height]
  end

  def test_defaults_apply_when_window_unconfigured
    app = Tokra::Builder.new.build(native: StubNative)

    assert_equal "Tokra", app.config[:title]
    assert_in_delta 800.0, app.config[:width]
  end

  def test_rack_app_is_served_over_tokra_protocol
    StubNative.inject_event(Tokra::Native::HttpRequestEvent.new(
      7, "GET", "tokra://localhost/greet", {}, ""
    ))
    Tokra::Builder.new.app(ECHO_APP).run(native: StubNative)

    responses = StubNative.responses
    assert_equal 1, responses.size, "the Rack app should answer the request through the proxy"
    request_id, status, _headers, body = responses.first
    assert_equal 7, request_id
    assert_equal 200, status
    assert_equal "echo:/greet", body
  ensure
    StubNative.clear_event
  end

  def test_explicit_protocol_handler_takes_precedence_over_rack_app
    StubNative.inject_event(Tokra::Native::HttpRequestEvent.new(
      1, "GET", "tokra://localhost/", {}, ""
    ))
    handler = Ractor.shareable_proc { |_ctx, _event| Tokra::Response.ok("from protocol handler") }
    Tokra::Builder.new
      .app(ECHO_APP)
      .register_uri_scheme_protocol("tokra", &handler)
      .run(native: StubNative)

    _id, _status, _headers, body = StubNative.responses.first
    assert_equal "from protocol handler", body,
      "an explicitly registered tokra handler should win over the Rack fallback"
  ensure
    StubNative.clear_event
  end

  def test_rack_served_webview_receives_ipc_scripts_and_responds
    # The whole point of unification: a Rack app's webview gets the
    # __TAURI_INTERNALS__ scripts and invoke() responses, which the old
    # Rack::Handler.run loop never provided.
    handler = Ractor.shareable_proc { |invoke|
      invoke.resolve("pong:#{invoke.payload['ping']}")
      true
    }
    app = Tokra::Builder.new.app(ECHO_APP).invoke_handler(&handler).build(native: StubNative)
    message = {
      "cmd" => "ping",
      "callback" => 10,
      "error" => 20,
      "payload" => { "ping" => "hi" },
      "__TAURI_INVOKE_KEY__" => app.invoke_key,
    }
    StubNative.inject_event(Tokra::Native::IpcEvent.new(JSON.generate(message), "tokra://localhost/"))

    app.run

    assert_equal ['window.__TAURI_INTERNALS__.runCallback(10, "pong:hi")'],
      app.handle.webviews["main"].native.evals
    refute_empty app.handle.webviews["main"].native.initialization_scripts,
      "a Rack-served webview should get the injected IPC scripts"
  ensure
    StubNative.clear_event
  end
end
