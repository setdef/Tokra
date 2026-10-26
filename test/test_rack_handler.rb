# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "support/local_origin"
require "stringio"

# Tests for Rack::Handler::Tokra
#
# These tests verify the Rack adapter behavior without requiring a display server.
# We test the handler's logic by mocking the native components and verifying
# the Ruby-level behavior.
#
# Strategy: Classicist for response data, Mockist for Proxy collaboration
class TestRackHandler < Minitest::Test
  # Mock Proxy that records #respond calls for verification
  class MockProxy
    attr_reader :responses

    def initialize
      @responses = []
    end

    def respond(request_id, status, headers, body)
      @responses << {
        request_id:,
        status:,
        headers: headers.to_h,
        body:,
      }
    end
  end

  # Mock HttpRequestEvent for testing without native extension
  # Note: Using :http_method instead of :method to avoid shadowing Struct#method
  MockHttpRequestEvent = Struct.new(:request_id, :uri, :http_method, :body, :headers, keyword_init: true) do
    alias_method :method, :http_method

    def initialize(request_id:, uri:, http_method:, body:, headers: [])
      super
    end
  end

  def setup
    @proxy = MockProxy.new
  end

  # ==========================================================================
  # Handler Instance Tests
  # ==========================================================================

  def test_initialize_stores_app_and_proxy
    app = -> (_env) { [200, {}, ["OK"]] }
    handler = Rack::Handler::Tokra.new(app, @proxy)

    assert_kind_of Rack::Handler::Tokra, handler
  end

  # ==========================================================================
  # #call - Basic Request Handling
  # ==========================================================================

  def test_call_translates_uri_to_rack_env_and_calls_app
    called_with_env = nil
    app = -> (env) {
      called_with_env = env
      [200, { "content-type" => "text/plain" }, ["Hello"]]
    }

    handler = Rack::Handler::Tokra.new(app, @proxy)
    event = MockHttpRequestEvent.new(
      request_id: 42,
      uri: "tokra://localhost/users?page=2",
      http_method: "GET",
      body: ""
    )

    handler.call(event)

    # Verify env was built correctly
    assert_equal "GET", called_with_env["REQUEST_METHOD"]
    assert_equal "/users", called_with_env["PATH_INFO"]
    assert_equal "page=2", called_with_env["QUERY_STRING"]
    assert_equal "localhost", called_with_env["SERVER_NAME"]
    assert_equal "80", called_with_env["SERVER_PORT"]
    assert_equal "tokra", called_with_env["rack.url_scheme"]
  end

  def test_call_sends_response_via_proxy_respond
    app = -> (_env) { [200, { "content-type" => "text/html" }, ["<h1>Hi</h1>"]] }
    handler = Rack::Handler::Tokra.new(app, @proxy)

    event = MockHttpRequestEvent.new(
      request_id: 99,
      uri: "tokra://localhost/",
      http_method: "GET",
      body: ""
    )

    handler.call(event)

    assert_equal 1, @proxy.responses.size
    response = @proxy.responses.first

    assert_equal 99, response[:request_id]
    assert_equal 200, response[:status]
    assert_equal "text/html", response[:headers]["content-type"]
    assert_equal "<h1>Hi</h1>", response[:body]
  end

  def test_call_handles_empty_path_as_root
    called_path = nil
    app = -> (env) {
      called_path = env["PATH_INFO"]
      [200, {}, ["OK"]]
    }

    handler = Rack::Handler::Tokra.new(app, @proxy)
    event = MockHttpRequestEvent.new(
      request_id: 1,
      uri: "tokra://localhost", # No path!
      http_method: "GET",
      body: ""
    )

    handler.call(event)

    assert_equal "/", called_path, "Empty path should default to /"
  end

  def test_call_passes_request_body_to_rack_input
    received_body = nil
    app = -> (env) {
      received_body = env["rack.input"].read
      [200, {}, ["OK"]]
    }

    handler = Rack::Handler::Tokra.new(app, @proxy)
    event = MockHttpRequestEvent.new(
      request_id: 1,
      uri: "tokra://localhost/api",
      http_method: "POST",
      body: '{"name": "test"}'
    )

    handler.call(event)

    assert_equal '{"name": "test"}', received_body
  end

  # ==========================================================================
  # Redirect Following (Critical for Mutation Testing!)
  # ==========================================================================

  def test_call_follows_301_redirect_internally
    call_count = 0
    app = -> (env) {
      call_count += 1
      if env["PATH_INFO"] == "/old"
        [301, { "location" => "/new" }, [""]]
      else
        [200, {}, ["Final destination"]]
      end
    }

    handler = Rack::Handler::Tokra.new(app, @proxy)
    event = MockHttpRequestEvent.new(
      request_id: 1,
      uri: "tokra://localhost/old",
      http_method: "GET",
      body: ""
    )

    handler.call(event)

    assert_equal 2, call_count, "Should call app twice (original + redirect)"
    assert_equal 200, @proxy.responses.first[:status]
    assert_equal "Final destination", @proxy.responses.first[:body]
  end

  def test_call_follows_302_redirect_internally
    app = -> (env) {
      if env["PATH_INFO"] == "/temp"
        [302, { "location" => "/permanent" }, [""]]
      else
        [200, {}, ["OK"]]
      end
    }

    handler = Rack::Handler::Tokra.new(app, @proxy)
    event = MockHttpRequestEvent.new(
      request_id: 1,
      uri: "tokra://localhost/temp",
      http_method: "POST",
      body: ""
    )

    handler.call(event)

    assert_equal 200, @proxy.responses.first[:status]
  end

  def test_call_converts_post_to_get_after_redirect_prg_pattern
    methods_received = []
    app = -> (env) {
      methods_received << env["REQUEST_METHOD"]
      if env["PATH_INFO"] == "/form"
        [303, { "location" => "/thanks" }, [""]]
      else
        [200, {}, ["Thanks!"]]
      end
    }

    handler = Rack::Handler::Tokra.new(app, @proxy)
    event = MockHttpRequestEvent.new(
      request_id: 1,
      uri: "tokra://localhost/form",
      http_method: "POST",
      body: "data=value"
    )

    handler.call(event)

    assert_equal ["POST", "GET"], methods_received,
      "POST should become GET after redirect (PRG pattern)"
  end

  def test_call_preserves_set_cookie_across_redirect_for_sessions
    app = -> (env) {
      if env["PATH_INFO"] == "/login"
        [302, { "location" => "/dashboard", "set-cookie" => "session=abc123" }, [""]]
      else
        cookie = env["HTTP_COOKIE"]
        [200, {}, ["Cookie: #{cookie}"]]
      end
    }

    handler = Rack::Handler::Tokra.new(app, @proxy)
    event = MockHttpRequestEvent.new(
      request_id: 1,
      uri: "tokra://localhost/login",
      http_method: "POST",
      body: ""
    )

    handler.call(event)

    assert_equal "Cookie: session=abc123", @proxy.responses.first[:body],
      "Set-Cookie from redirect should propagate to next request"
  end

  def test_call_returns_508_on_redirect_loop_after_max_redirects
    # MAX_REDIRECTS is 10, so we need 11 redirects to trigger
    redirect_count = 0
    app = -> (_env) {
      redirect_count += 1
      [302, { "location" => "/loop" }, [""]]
    }

    handler = Rack::Handler::Tokra.new(app, @proxy)
    event = MockHttpRequestEvent.new(
      request_id: 1,
      uri: "tokra://localhost/loop",
      http_method: "GET",
      body: ""
    )

    handler.call(event)

    # Should stop at MAX_REDIRECTS + 1 (the triggering request)
    assert_equal 11, redirect_count, "Should attempt exactly MAX_REDIRECTS + 1 requests"
    assert_equal 508, @proxy.responses.first[:status], "Should return 508 Loop Detected"
    assert_includes @proxy.responses.first[:body], "Too many redirects"
  end

  def test_call_does_not_follow_299_as_redirect
    app = -> (env) {
      if env["PATH_INFO"] == "/almost"
        [299, { "location" => "/nope" }, ["Not a redirect"]]
      else
        [200, {}, ["Wrong path"]]
      end
    }

    handler = Rack::Handler::Tokra.new(app, @proxy)
    event = MockHttpRequestEvent.new(
      request_id: 1,
      uri: "tokra://localhost/almost",
      http_method: "GET",
      body: ""
    )

    handler.call(event)

    assert_equal 299, @proxy.responses.first[:status],
      "299 should not be treated as redirect (boundary test)"
  end

  def test_call_does_not_follow_400_as_redirect
    app = -> (env) {
      if env["PATH_INFO"] == "/error"
        [400, { "location" => "/nope" }, ["Bad Request"]]
      else
        [200, {}, ["Wrong path"]]
      end
    }

    handler = Rack::Handler::Tokra.new(app, @proxy)
    event = MockHttpRequestEvent.new(
      request_id: 1,
      uri: "tokra://localhost/error",
      http_method: "GET",
      body: ""
    )

    handler.call(event)

    assert_equal 400, @proxy.responses.first[:status],
      "400 should not be treated as redirect (boundary test)"
  end

  def test_call_requires_location_header_for_redirect
    app = -> (_env) {
      [302, {}, ["Redirect without location"]] # Missing location header!
    }

    handler = Rack::Handler::Tokra.new(app, @proxy)
    event = MockHttpRequestEvent.new(
      request_id: 1,
      uri: "tokra://localhost/",
      http_method: "GET",
      body: ""
    )

    handler.call(event)

    assert_equal 302, @proxy.responses.first[:status],
      "302 without location should not redirect"
    assert_equal "Redirect without location", @proxy.responses.first[:body]
  end

  # ==========================================================================
  # build_env Tests (via observable behavior)
  # ==========================================================================

  def test_build_env_sets_all_required_rack_keys
    observed_env = nil
    app = -> (env) {
      observed_env = env
      [200, {}, [""]]
    }

    handler = Rack::Handler::Tokra.new(app, @proxy)
    event = MockHttpRequestEvent.new(
      request_id: 1,
      uri: "tokra://localhost/path?query=1",
      http_method: "DELETE",
      body: "body"
    )

    handler.call(event)

    # Required Rack spec keys
    assert_equal "DELETE", observed_env["REQUEST_METHOD"]
    assert_equal "", observed_env["SCRIPT_NAME"]
    assert_equal "/path", observed_env["PATH_INFO"]
    assert_equal "query=1", observed_env["QUERY_STRING"]
    assert_equal "localhost", observed_env["SERVER_NAME"]
    assert_equal "80", observed_env["SERVER_PORT"]

    # rack.* keys
    assert_equal [2, 0], observed_env["rack.version"]
    assert_equal "tokra", observed_env["rack.url_scheme"]
    assert_kind_of StringIO, observed_env["rack.input"]
    assert_equal $stderr, observed_env["rack.errors"]
    assert_equal false, observed_env["rack.multithread"]
    assert_equal false, observed_env["rack.multiprocess"]
    assert_equal false, observed_env["rack.run_once"]
  end

  def test_build_env_handles_nil_query_string
    observed_query = "UNSET"
    app = -> (env) {
      observed_query = env["QUERY_STRING"]
      [200, {}, [""]]
    }

    handler = Rack::Handler::Tokra.new(app, @proxy)
    event = MockHttpRequestEvent.new(
      request_id: 1,
      uri: "tokra://localhost/no-query", # No query string
      http_method: "GET",
      body: ""
    )

    handler.call(event)

    assert_equal "", observed_query, "Missing query string should be empty string"
  end

  # ==========================================================================
  # Response Body Handling
  # ==========================================================================

  def test_call_concatenates_body_chunks
    app = -> (_env) {
      body = ["Hello", " ", "World", "!"]
      [200, {}, body]
    }

    handler = Rack::Handler::Tokra.new(app, @proxy)
    event = MockHttpRequestEvent.new(
      request_id: 1,
      uri: "tokra://localhost/",
      http_method: "GET",
      body: ""
    )

    handler.call(event)

    assert_equal "Hello World!", @proxy.responses.first[:body]
  end

  def test_call_closes_body_if_responds_to_close
    closed = false
    body_proxy = Object.new
    body_proxy.define_singleton_method(:each) { |&block| block.call("data") }
    body_proxy.define_singleton_method(:close) { closed = true }

    app = -> (_env) { [200, {}, body_proxy] }

    handler = Rack::Handler::Tokra.new(app, @proxy)
    event = MockHttpRequestEvent.new(
      request_id: 1,
      uri: "tokra://localhost/",
      http_method: "GET",
      body: ""
    )

    handler.call(event)

    assert closed, "Body#close should be called"
  end

  # ==========================================================================
  # DEFAULT_OPTIONS
  # ==========================================================================

  def test_default_options_are_frozen
    assert Rack::Handler::Tokra::DEFAULT_OPTIONS.frozen?
  end

  def test_default_options_contain_expected_keys
    opts = Rack::Handler::Tokra::DEFAULT_OPTIONS

    assert_equal "Tokra", opts[:title]
    assert_equal 800.0, opts[:width]
    assert_equal 600.0, opts[:height]
  end

  def test_max_redirects_is_10
    assert_equal 10, Rack::Handler::Tokra::MAX_REDIRECTS
  end

  # ==========================================================================
  # Header Forwarding (ADR 002 / Plan 003)
  #
  # WKWebView custom protocols don't auto-persist cookies, so Tokra's Rust
  # layer extracts headers from WKURLSchemeTask and forwards them to Ruby.
  # Only the Cookie header is forwarded to avoid rendering issues from other
  # headers (Accept-Encoding, etc.).
  # ==========================================================================

  def test_call_forwards_cookie_header_to_rack_env
    received_cookie = nil
    app = -> (env) {
      received_cookie = env["HTTP_COOKIE"]
      [200, {}, ["OK"]]
    }

    handler = Rack::Handler::Tokra.new(app, @proxy)
    event = MockHttpRequestEvent.new(
      request_id: 1,
      uri: "tokra://localhost/",
      http_method: "GET",
      body: "",
      headers: [["Cookie", "_session=abc123; csrf=xyz789"]]
    )

    handler.call(event)

    assert_equal "_session=abc123; csrf=xyz789", received_cookie,
      "Cookie header should be forwarded to HTTP_COOKIE"
  end

  def test_call_forwards_cookie_header_case_insensitively
    received_cookie = nil
    app = -> (env) {
      received_cookie = env["HTTP_COOKIE"]
      [200, {}, ["OK"]]
    }

    handler = Rack::Handler::Tokra.new(app, @proxy)

    # Test lowercase (as sent by WKWebView)
    event = MockHttpRequestEvent.new(
      request_id: 1,
      uri: "tokra://localhost/",
      http_method: "GET",
      body: "",
      headers: [["cookie", "session=lowercase"]]
    )
    handler.call(event)

    assert_equal "session=lowercase", received_cookie,
      "Lowercase 'cookie' header should be forwarded"
  end

  def test_call_does_not_forward_non_cookie_headers
    env_keys_with_http = nil
    app = -> (env) {
      # Collect all HTTP_* keys (excluding standard Rack ones)
      env_keys_with_http = env.keys.select { |k| k.start_with?("HTTP_") }
      [200, {}, ["OK"]]
    }

    handler = Rack::Handler::Tokra.new(app, @proxy)
    event = MockHttpRequestEvent.new(
      request_id: 1,
      uri: "tokra://localhost/",
      http_method: "GET",
      body: "",
      headers: [
        ["Accept-Encoding", "gzip, deflate"],
        ["User-Agent", "Mozilla/5.0"],
        ["Accept", "text/html"],
      ]
    )

    handler.call(event)

    assert_empty env_keys_with_http,
      "Non-Cookie headers should not be forwarded (Accept-Encoding caused render issues)"
  end

  def test_call_forwards_cookie_but_skips_other_headers
    received_headers = {}
    app = -> (env) {
      received_headers = env.select { |k, _| k.start_with?("HTTP_") }
      [200, {}, ["OK"]]
    }

    handler = Rack::Handler::Tokra.new(app, @proxy)
    event = MockHttpRequestEvent.new(
      request_id: 1,
      uri: "tokra://localhost/",
      http_method: "POST",
      body: "",
      headers: [
        ["cookie", "session=forward_me"],
        ["accept-encoding", "gzip"],
        ["content-type", "application/json"],
      ]
    )

    handler.call(event)

    assert_equal 1, received_headers.size, "Only Cookie should be forwarded"
    assert_equal "session=forward_me", received_headers["HTTP_COOKIE"]
  end

  def test_call_handles_empty_headers_gracefully
    called = false
    app = -> (env) {
      called = true
      # Verify no crash with empty headers
      assert_nil env["HTTP_COOKIE"]
      [200, {}, ["OK"]]
    }

    handler = Rack::Handler::Tokra.new(app, @proxy)
    event = MockHttpRequestEvent.new(
      request_id: 1,
      uri: "tokra://localhost/",
      http_method: "GET",
      body: "",
      headers: []
    )

    handler.call(event)

    assert called, "Handler should complete with empty headers"
  end

  def test_call_cookie_header_survives_mutation_by_checking_exact_value
    # This test specifically checks that the cookie VALUE is preserved exactly
    # A mutation that strips characters or modifies the value would fail
    received_cookie = nil
    app = -> (env) {
      received_cookie = env["HTTP_COOKIE"]
      [200, {}, ["OK"]]
    }

    handler = Rack::Handler::Tokra.new(app, @proxy)
    # Use a complex cookie with special characters
    complex_cookie = "_verify=Base64%2BEncoded%3D%3D; path=/; httponly"
    event = MockHttpRequestEvent.new(
      request_id: 1,
      uri: "tokra://localhost/",
      http_method: "GET",
      body: "",
      headers: [["Cookie", complex_cookie]]
    )

    handler.call(event)

    assert_equal complex_cookie, received_cookie,
      "Cookie value must be preserved exactly (not truncated or modified)"
  end

  def test_call_redirect_cookies_override_event_cookies
    # When a redirect sets a cookie, it should override the incoming Cookie header
    # This ensures session updates during login/logout work correctly
    cookies_received = []
    app = -> (env) {
      cookies_received << env["HTTP_COOKIE"]
      if env["PATH_INFO"] == "/login"
        [302, { "location" => "/dashboard", "set-cookie" => "session=new_session" }, [""]]
      else
        [200, {}, ["OK"]]
      end
    }

    handler = Rack::Handler::Tokra.new(app, @proxy)
    event = MockHttpRequestEvent.new(
      request_id: 1,
      uri: "tokra://localhost/login",
      http_method: "POST",
      body: "",
      headers: [["Cookie", "session=old_session"]]
    )

    handler.call(event)

    # First request should use the event's cookie
    assert_equal "session=old_session", cookies_received[0]
    # After redirect, the Set-Cookie from redirect should be used
    assert_equal "session=new_session", cookies_received[1]
  end
  # ==========================================================================
  # Binary bodies (Plan 016 #2)
  # ==========================================================================

  # Rack::Files answers with a to_path body. A PNG is not text, so the
  # handler must hand the proxy the file's exact bytes.
  def test_call_serves_a_binary_file_body_byte_exact
    require "rack/files"
    fixtures = File.expand_path("fixtures", __dir__)
    handler = Rack::Handler::Tokra.new(Rack::Files.new(fixtures), @proxy)

    handler.call(MockHttpRequestEvent.new(request_id: 5, uri: "tokra://localhost/2x2.png",
      http_method: "GET", body: ""))

    response = @proxy.responses.first
    assert_equal 200, response[:status]
    assert_equal "image/png", response[:headers]["content-type"]
    assert_equal File.binread(File.join(fixtures, "2x2.png")), response[:body]
    assert_equal Encoding::BINARY, response[:body].encoding, "the body is bytes, not text"
  end

  # A body mixing a non-ASCII UTF-8 chunk with a binary chunk would raise
  # Encoding::CompatibilityError if concatenated as text.
  def test_call_joins_mixed_utf8_and_binary_chunks_as_bytes
    utf8 = "café"
    binary = "\xFF\x00".b
    { "to_ary" => [utf8, binary], "each" => Enumerator.new { |y| y << utf8 << binary } }.each do |kind, body|
      proxy = MockProxy.new
      handler = Rack::Handler::Tokra.new(-> (_env) { [200, {}, body] }, proxy)

      handler.call(MockHttpRequestEvent.new(request_id: 1, uri: "tokra://localhost/", http_method: "GET", body: ""))

      assert_equal "café".b + "\xFF\x00".b, proxy.responses.first[:body], "#{kind} bodies join as bytes"
      assert_equal Encoding::BINARY, proxy.responses.first[:body].encoding
    end
  end

  # ==========================================================================
  # Rack::Handler::Tokra.run (porcelain over Tokra::Builder)
  # ==========================================================================

  def test_run_forwards_title_size_global_tauri_and_invoke_handler
    require_relative "support/stub_native"
    Thread.current[:invoked] = nil
    handler = Ractor.shareable_proc { |invoke|
      Thread.current[:invoked] = invoke.command
      invoke.resolve("pong")
      true
    }
    StubNative.inject_event(Tokra::Native::IpcEvent.new(
      JSON.generate("cmd" => "ping", "callback" => 1, "error" => 2, "__TAURI_INVOKE_KEY__" => "known-key"),
      LocalOrigin.url
    ))

    Tokra.stub(:generate_invoke_key, "known-key") do
      Rack::Handler::Tokra.run(-> (_env) { [200, {}, ["ok"]] },
        title: "Forwarded", width: 640, height: 480, with_global_tauri: true,
        invoke_handler: handler, native: StubNative)
    end

    window = StubNative.windows.last
    assert_equal "Forwarded", window.title
    assert_equal [640.0, 480.0], window.size
    assert_equal "ping", Thread.current[:invoked], "the invoke handler receives frontend invokes"
    webview = StubNative::WebView.instances.last
    assert_includes webview.initialization_scripts.last, "__TAURI_IIFE__",
      "with_global_tauri reaches the builder"
    assert_equal [%q{window.__TAURI_INTERNALS__.runCallback(1, "pong")}], webview.evals
  ensure
    StubNative.clear_event
  end
end
