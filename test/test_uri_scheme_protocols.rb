# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "support/local_origin"
require_relative "support/stub_native"
require_relative "support/test_app"

# Every custom URI scheme the builder holds is registered on each webview
# and reaches its handler (plan 067). Tauri registers each scheme its
# manager holds, then its own tauri and ipc protocols unless a held scheme
# took the name (manager/webview.rs:222-280), keeps one map for both kinds
# of handler (app.rs:1981-2066), and counts a page from a held scheme as
# the app's own (webview/mod.rs:1696-1722).
class TestUriSchemeProtocols < Minitest::Test
  N = Tokra::Native

  # Answers a page naming the scheme and the webview it served.
  SECOND = Ractor.shareable_proc do |ctx, request|
    Thread.current[:schemes] << [:second, ctx.webview_label, request.uri]
    Tokra::Response.ok("second for #{ctx.webview_label}")
  end

  # Answers through its responder.
  THIRD = Ractor.shareable_proc do |ctx, request, responder|
    Thread.current[:schemes] << [:third, ctx.webview_label, request.uri]
    responder.respond(Tokra::Response.ok("third", content_type: "application/json"))
  end

  # Logs a synchronous registration's call.
  SYNC = Ractor.shareable_proc do |_ctx, _request|
    Thread.current[:schemes] << :sync
    Tokra::Response.ok("sync")
  end

  # Logs an asynchronous registration's call.
  ASYNC = Ractor.shareable_proc do |_ctx, _request, responder|
    Thread.current[:schemes] << :async
    responder.respond(Tokra::Response.ok("async"))
  end

  # Answers an invoke.
  PING = Ractor.shareable_proc do |invoke|
    invoke.resolve("PONG")
    true
  end

  def setup
    Thread.current[:schemes] = []
  end

  def teardown
    StubNative.clear_event
  end

  def test_a_request_on_a_held_scheme_reaches_its_handler_with_the_webview
    run_app(-> (b) { b.register_uri_scheme_protocol("second", &SECOND) }) do
      [request("second", "second://localhost/index.html")]
    end

    assert_equal [[:second, "main", "second://localhost/index.html"]], log
    assert_equal [[5, 200, [["content-type", "text/html"]], "second for main"]], StubNative.responses
  end

  def test_an_asynchronous_handler_answers_through_its_responder
    run_app(-> (b) { b.register_asynchronous_uri_scheme_protocol("third", &THIRD) }) do
      [request("third", "third://localhost/data")]
    end

    assert_equal [[:third, "main", "third://localhost/data"]], log
    assert_equal [[5, 200, [["content-type", "application/json"]], "third"]], StubNative.responses
  end

  # The request names the scheme its protocol was registered under, and
  # that, not the URI, picks the handler, as each of Tauri's protocols is
  # its own closure (manager/webview.rs:224-234).
  def test_the_registration_and_not_the_uri_picks_the_handler
    run_app(-> (b) { b.register_uri_scheme_protocol("Second", &SECOND) }) do
      [request("Second", "second://localhost/")]
    end

    assert_equal [[:second, "main", "second://localhost/"]], log
  end

  def test_the_later_registration_of_a_scheme_wins_whatever_its_kind
    run_app(lambda { |b|
      b.register_uri_scheme_protocol("second", &SYNC).register_asynchronous_uri_scheme_protocol("second", &ASYNC)
    }) { [request("second", "second://localhost/")] }
    run_app(lambda { |b|
      b.register_asynchronous_uri_scheme_protocol("second", &ASYNC).register_uri_scheme_protocol("second", &SYNC)
    }) { [request("second", "second://localhost/")] }

    assert_equal %i[async sync], log
  end

  # A held ipc takes the name from Tokra's transport, as a held one does
  # from Tauri's (manager/webview.rs:273-280).
  def test_a_held_ipc_scheme_replaces_the_invoke_transport
    run_app(lambda { |b|
      b.register_uri_scheme_protocol("ipc", &SECOND).invoke_handler(&PING)
    }) { |built| [ipc_invoke(built)] }

    assert_equal [[:second, "main", "ipc://localhost/ping"]], log
    assert_equal "second for main", StubNative.responses.last.last
  end

  def test_without_a_held_ipc_scheme_the_transport_answers
    run_app(-> (b) { b.register_uri_scheme_protocol("second", &SECOND).invoke_handler(&PING) }) do |built|
      [ipc_invoke(built)]
    end

    assert_empty log
    assert_equal '"PONG"', StubNative.responses.last.last
  end

  # A held tokra takes the name from the Rack app, as a held tauri does
  # from Tauri's asset protocol (manager/webview.rs:259-271).
  def test_a_held_tokra_scheme_replaces_the_rack_app
    rack = -> (_env) { [200, { "content-type" => "text/plain" }, ["rack"]] }
    run_app(-> (b) { b.app(rack).register_uri_scheme_protocol("tokra", &SECOND) }) do
      [request("tokra", "tokra://localhost/")]
    end

    assert_equal [[:second, "main", "tokra://localhost/"]], log
  end

  # Not even the Rack app's: it serves tokra:// only.
  def test_a_request_on_a_scheme_nothing_holds_gets_no_answer
    rack = -> (_env) { [200, { "content-type" => "text/plain" }, ["rack"]] }
    run_app(-> (b) { b.app(rack).register_uri_scheme_protocol("second", &SECOND) }) do
      [request("fourth", "fourth://localhost/")]
    end

    assert_empty log
    assert_empty StubNative.responses
  end

  # The held schemes in the order they were registered, then tokra, then
  # ipc, each unless held (manager/webview.rs:222-280).
  def test_each_webview_registers_the_held_schemes_then_tokra_and_ipc
    run_app(lambda { |b|
      b.register_uri_scheme_protocol("second", &SECOND).register_asynchronous_uri_scheme_protocol("third", &THIRD)
    }) { [] }

    assert_equal %w[second third tokra ipc], main_webview.uri_scheme_protocols
  end

  def test_a_held_built_in_name_is_registered_once
    run_app(lambda { |b|
      b.register_uri_scheme_protocol("ipc", &SECOND).register_uri_scheme_protocol("tokra", &SECOND)
    }) { [] }

    assert_equal %w[ipc tokra], main_webview.uri_scheme_protocols
  end

  def test_without_a_held_scheme_a_webview_registers_tokra_and_ipc
    run_app(nil) { [] }

    assert_equal %w[tokra ipc], main_webview.uri_scheme_protocols
  end

  # The third arm of is_local_url (webview/mod.rs:1696-1722): on macOS and
  # Linux a page whose scheme is held; on Windows one whose domain's first
  # label is held, over the app's http or https.
  def test_a_page_from_a_held_scheme_is_the_apps_own
    app = build_test_app(Tokra::Builder.default.register_uri_scheme_protocol("second", &SECOND))
    origins = %w[
      second://localhost/
      second://elsewhere/
      fourth://localhost/
      http://second.localhost/
      https://second.localhost/
      http://fourth.localhost/
      http://localhost/
      ftp://second.localhost/
    ]
    results = %w[macos linux windows].to_h do |os_name|
      [os_name, origins.map { |origin| app.stub(:os_name, os_name) { app.__send__(:local_url?, origin) } }]
    end

    assert_equal({
      "macos" => [true, true, false, false, false, false, false, false],
      "linux" => [true, true, false, false, false, false, false, false],
      "windows" => [false, false, false, true, true, false, false, false],
    }, results)
  end

  def test_an_invoke_from_a_held_scheme_is_answered_and_from_another_rejected
    origin = -> (scheme) { (Tokra::App.os_name == "windows") ? "http://#{scheme}.localhost" : "#{scheme}://localhost" }
    run_app(-> (b) { b.register_uri_scheme_protocol("second", &SECOND).invoke_handler(&PING) }) do |built|
      [ipc_invoke(built, origin: origin.call("second")), ipc_invoke(built, origin: origin.call("fourth"))]
    end

    assert_equal ['"PONG"', '"Command ping not allowed by ACL"'], StubNative.responses.map(&:last)
  end

  # A plugin's schemes go to the app's webview manager when the plugin
  # initializes, and every webview made after registers them
  # (plugin.rs:635-724, 810-815). Its blocks need not be Ractor-shareable
  # (plan 064, decision 4).
  def test_a_plugins_scheme_reaches_its_handler
    heard = []
    plugin = Tokra::Plugin::Builder.new("files")
      .register_uri_scheme_protocol("second") do |ctx, request|
        heard << [ctx.webview_label, request.uri]
        Tokra::Response.ok("from the plugin")
      end
      .build
    run_app(-> (b) { b.plugin(plugin) }) { [request("second", "second://localhost/a.png")] }

    assert_equal [["main", "second://localhost/a.png"]], heard
    assert_equal [[5, 200, [["content-type", "text/html"]], "from the plugin"]], StubNative.responses
    assert_equal %w[second tokra ipc], main_webview.uri_scheme_protocols
  end

  def test_a_plugins_asynchronous_scheme_answers_through_its_responder
    plugin = Tokra::Plugin::Builder.new("files").register_asynchronous_uri_scheme_protocol("third", &THIRD).build
    run_app(-> (b) { b.plugin(plugin) }) { [request("third", "third://localhost/data")] }

    assert_equal [[:third, "main", "third://localhost/data"]], log
    assert_equal [[5, 200, [["content-type", "application/json"]], "third"]], StubNative.responses
  end

  # The builder's plugins initialize after the app's own schemes are held,
  # so a plugin's scheme replaces the app's of the same name, as Tauri's
  # map insert does (app.rs:2289; manager/webview.rs:98-108).
  def test_a_plugins_scheme_replaces_the_apps_of_the_same_name
    plugin = Tokra::Plugin::Builder.new("files").register_uri_scheme_protocol("second", &SYNC).build
    run_app(-> (b) { b.register_uri_scheme_protocol("second", &SECOND).plugin(plugin) }) do
      [request("second", "second://localhost/")]
    end

    assert_equal [:sync], log
  end

  # Tauri's initialize returns at a failed setup, before the protocols are
  # registered (plugin.rs:793-815).
  def test_a_plugin_whose_setup_fails_registers_no_scheme
    app = build_test_app
    plugin = Tokra::Plugin::Builder.new("files")
      .register_uri_scheme_protocol("second", &SYNC)
      .setup { |_app, _api| raise "no files" }
      .build

    assert_raises(Tokra::Error::PluginInitialization) { app.handle.plugin(plugin) }
    refute app.handle.webview_manager.uri_scheme_protocols.key?("second")
  end

  def test_a_plugins_scheme_needs_a_block
    builder = Tokra::Plugin::Builder.new("files")

    assert_raises(ArgumentError) { builder.register_uri_scheme_protocol("second") }
    assert_raises(ArgumentError) { builder.register_asynchronous_uri_scheme_protocol("second") }
  end

  private def log = Thread.current[:schemes]

  private def main_webview
    StubNative::WebView.instances.find { |webview| webview.label == "main" }
  end

  # Builds an app from a builder +configure+ changes, queues the events the
  # block answers for it, and runs it.
  private def run_app(configure)
    StubNative.responses.clear
    builder = Tokra::Builder.default
    builder = configure.call(builder) if configure
    app = build_test_app(builder)
    StubNative.inject_event(yield(app))
    app.run
    app
  rescue SystemExit
    app
  end

  private def request(scheme, uri, label: "main")
    N::HttpRequestEvent.new(label:, request_id: 5, method: "GET", uri:, headers: [], body: "", scheme:)
  end

  private def ipc_invoke(app, origin: LocalOrigin.url("", app:))
    headers = [
      ["content-type", "application/json"],
      ["tauri-callback", "1"],
      ["tauri-error", "2"],
      ["tauri-invoke-key", app.invoke_key],
      ["origin", origin],
    ]
    N::HttpRequestEvent.new(label: "main", request_id: 6, method: "POST", uri: "ipc://localhost/ping",
      headers:, body: "{}", scheme: "ipc")
  end
end
