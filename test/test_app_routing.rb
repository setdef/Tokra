# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "support/local_origin"
require_relative "support/stub_native"
require_relative "support/test_app"

# Every native event names its window or webview, and App routes it there
# (plan 052, phase 1). Tauri's runtime resolves a window event's window
# through its window_id_map and a webview event's webview by its label
# (tauri-runtime-wry lib.rs:4126-4150, 5169-5192; manager/webview.rs:229-233,
# 282-300; ipc/protocol.rs:32-36, 59-61, 152-160).
#
# Beside App's own "main", the setup hook builds a second stub window
# "second" holding a webview "side" and registers both by hand, as phase 2's
# builder will.
class TestAppRouting < Minitest::Test
  N = Tokra::Native
  W = Tokra::WindowEvent

  # Builds "second" and "side" with the native module the test runs, and
  # logs what "second"'s own listener hears.
  SECOND = Ractor.shareable_proc do |app|
    handle = app.app_handle
    native = Thread.current[:routing_native]
    native_window = native.const_get(:Window).new(handle.runtime_context.window_target, "second")
    native_window.state[:inner_size] = [640, 480]
    window = Tokra::Window.new(label: "second", native: native_window, app_handle: handle)
    window.on_window_event { |event| Thread.current[:routing] << [:listener, "second", event.class] }
    handle.windows["second"] = window
    native_webview = native.const_get(:WebView).new_with_protocol(native_window, nil, "side", [])
    handle.webviews["side"] = Tokra::Webview.new(label: "side", native: native_webview, window:, app_handle: handle)
  end

  # Logs what each window App builds hears through Builder#on_window_event.
  BUILDER_LISTENER = Ractor.shareable_proc do |window, event|
    Thread.current[:routing] << [:builder, window.label, event.class]
  end

  # Answers the label of the webview that invoked it.
  WHOAMI = Ractor.shareable_proc do |invoke|
    Thread.current[:routing] << [:invoked, invoke.webview.label]
    invoke.resolve(invoke.webview.label)
    true
  end

  # Hears every page load after the builder's hook, logged by its name.
  class PageLoadPlugin < Tokra::Plugin
    def name = "plugin_a"

    def on_page_load(webview, payload)
      Thread.current[:routing] << [name.to_sym, webview, payload]
    end
  end

  # A second recorder, registered after the first.
  class LaterPageLoadPlugin < PageLoadPlugin
    def name = "plugin_b"
  end

  # StubNative whose webviews take a theme, as Native::WebView does on
  # Windows, recording which webview took it.
  module ThemedNative
    StubNative.constants.each { |name| const_set(name, StubNative.const_get(name)) unless name == :WebView }

    class WebView < StubNative::WebView
      def set_theme(name)
        Thread.current[:routing] << [:set_theme, label, name]
        nil
      end
    end
  end

  def setup
    Thread.current[:routing] = []
  end

  def test_a_close_request_closes_only_its_window
    run_app { [N::WindowCloseEvent.new("second")] }

    assert_includes log, [:listener, "second", W::CloseRequested]
    assert_includes log, [:run, "second", W::CloseRequested]
    refute_includes log, [:builder, "main", W::CloseRequested]
    assert_predicate native_window("second"), :closed?
    refute_predicate native_window("main"), :closed?
    refute_includes log, [:exit_requested]
  end

  def test_destroyed_drops_its_window_and_webviews_and_exits_after_the_last
    app = run_app { [N::WindowDestroyedEvent.new("second"), N::WindowDestroyedEvent.new("main")] }

    assert_includes log, [:manager, "second", %w[main], %w[main]]
    assert_predicate native_webview("side"), :closed?
    asks = log.each_index.select { |i| log[i] == [:exit_requested] }
    assert_equal 1, asks.size, "only the last window's Destroyed asks to exit"
    assert_operator asks.first, :>, log.index([:run, "main", W::Destroyed])
    assert_equal 0, StubNative.exit_code
    assert_empty app.handle.windows
  end

  def test_each_window_event_reaches_only_its_window
    {
      N::WindowResizedEvent.new("second") => W::Resized,
      N::WindowMovedEvent.new("second", -5, 40) => W::Moved,
      N::WindowFocusedEvent.new("second", true) => W::Focused,
      N::WindowScaleFactorChangedEvent.new("second", 1.5, 1200, 900) => W::ScaleFactorChanged,
      N::WindowThemeChangedEvent.new("second", "dark") => W::ThemeChanged,
    }.each do |event, kind|
      log.clear
      StubNative.clear_event
      run_app { [event] }

      assert_includes log, [:listener, "second", kind], kind.name
      assert_includes log, [:run, "second", kind], kind.name
      assert_empty log.select { |entry| entry[0] == :builder }, "main hears no #{kind.name}"
    end
  end

  # Tauri's runtime reads the size of the window the event names
  # (tauri-runtime-wry lib.rs:557-575).
  def test_a_resize_carries_its_windows_inner_size
    run_app { [N::WindowResizedEvent.new("second")] }

    assert_includes log, [:size, "second", Tokra::PhysicalSize.new(width: 640, height: 480)]
  end

  def test_an_event_for_an_unknown_window_or_webview_reaches_nothing
    _, err = capture_io do
      run_app do |app|
        [
          N::WindowCloseEvent.new("ghost"),
          N::WindowDestroyedEvent.new("ghost"),
          N::WindowResizedEvent.new("ghost"),
          N::WindowMovedEvent.new("ghost", 1, 2),
          N::WindowFocusedEvent.new("ghost", true),
          N::WindowScaleFactorChangedEvent.new("ghost", 2.0, 1, 1),
          N::WindowThemeChangedEvent.new("ghost", "dark"),
          N::DragDropEvent.new("ghost", "leave", [], 0, 0),
          N::WebviewFocusedEvent.new("ghost", true),
          N::PageLoadEvent.new("ghost", "finished", "tokra://localhost/"),
          ipc_event(app, "ghost"),
          N::IpcEvent.new("ghost", "[]", LocalOrigin.url(app:)),
        ]
      end
    end

    assert_empty log
    assert_empty err
    assert_empty native_webview("main").evals + native_webview("side").evals
  end

  def test_a_post_message_invoke_answers_in_the_webview_that_sent_it
    run_app(invoke: true) { |app| [ipc_event(app, "side")] }

    assert_equal [[:invoked, "side"]], log
    assert_equal ['window.__TAURI_INTERNALS__.runCallback(1, "side")'], native_webview("side").evals
    assert_empty native_webview("main").evals
  end

  def test_a_post_message_from_an_unknown_webview_is_dropped
    run_app(invoke: true) { |app| [ipc_event(app, "ghost")] }

    assert_empty log
    assert_empty native_webview("main").evals + native_webview("side").evals
  end

  def test_a_post_message_tauri_cannot_read_is_reported_in_its_webview
    run_app { |app| [N::IpcEvent.new("side", '{"cmd":5}', LocalOrigin.url(app:))] }

    assert_equal ['console.error("JSON error: invalid type: integer `5`, expected a string")'],
      native_webview("side").evals
    assert_empty native_webview("main").evals
  end

  # Tauri looks the webview up first, so a request from an unknown webview
  # answers 500 even when its invoke key is wrong (ipc/protocol.rs:59-61,
  # 152-160).
  def test_an_ipc_protocol_post_from_an_unknown_webview_answers_500_before_the_key_check
    _, err = capture_io { run_app { [ipc_request("ghost", key: "wrong")] } }

    assert_equal [
[
  7,
  500,
  [["Content-Type", "text/plain"]] + Tokra::App::IPC_CORS_HEADERS,
  "failed to acquire webview reference",
],
], StubNative.responses
    assert_empty StubNative.dropped
    refute_match(/__TAURI_INVOKE_KEY__/, err)
  end

  def test_an_ipc_protocol_preflight_never_looks_the_webview_up
    run_app { [ipc_request("ghost", method: "OPTIONS")] }

    assert_equal [[7, 200, [["Access-Control-Allow-Headers", "*"]] + Tokra::App::IPC_CORS_HEADERS, ""]],
      StubNative.responses
  end

  def test_an_ipc_protocol_invoke_names_the_webview_that_sent_it
    run_app(invoke: true) { |app| [ipc_request("side", key: app.invoke_key)] }

    assert_equal [[:invoked, "side"]], log
    assert_equal '"side"', StubNative.responses.last.last
  end

  def test_a_protocol_request_names_its_webview_in_the_context
    handler = Ractor.shareable_proc { |ctx, _request|
      Thread.current[:routing] << [:context, ctx.webview_label]
      Tokra::Response.ok("")
    }
    run_app(builder: -> (b) { b.register_uri_scheme_protocol("tokra", &handler) }) { [tokra_request("side")] }

    assert_equal [[:context, "side"]], log
  end

  def test_an_asynchronous_protocol_request_names_its_webview_in_the_context
    handler = Ractor.shareable_proc { |ctx, _request, responder|
      Thread.current[:routing] << [:context, ctx.webview_label]
      responder.respond(Tokra::Response.ok(""))
    }
    run_app(builder: -> (b) { b.register_asynchronous_uri_scheme_protocol("tokra", &handler) }) { [tokra_request("side")] }

    assert_equal [[:context, "side"]], log
  end

  # The builder's hook, then every plugin's, with the webview that loaded
  # the page (manager/webview.rs:282-300; plugin.rs:965-972).
  def test_a_page_load_reaches_the_hook_and_then_the_plugins_with_its_webview
    hook = Ractor.shareable_proc { |webview, payload| Thread.current[:routing] << [:hook, webview, payload] }
    app = run_app(builder: -> (b) { b.on_page_load(&hook) }, plugin: true) do
      [N::PageLoadEvent.new("side", "finished", "tokra://localhost/")]
    end

    side = app.handle.webviews["side"]
    assert_equal [:hook, :plugin_a, :plugin_b], log.map(&:first), "the hook, then plugins in registration order"
    assert_same side, log[0][1]
    assert_same side, log[1][1]
    assert_same side, log[2][1]
    assert_same log[0][2], log[1][2], "all hear one payload"
    assert_same log[0][2], log[2][2], "all hear one payload"
    assert_equal Tokra::PageLoadPayload.new(url: "tokra://localhost/", started: false), log[0][2]
  end

  def test_a_page_load_in_an_unknown_webview_reaches_no_hook
    hook = Ractor.shareable_proc { |webview, payload| Thread.current[:routing] << [:hook, webview, payload] }
    run_app(builder: -> (b) { b.on_page_load(&hook) }, plugin: true) do
      [N::PageLoadEvent.new("ghost", "started", "tokra://localhost/")]
    end

    assert_empty log
  end

  # A webview's drops are its current window's (tauri-runtime-wry
  # lib.rs:4097-4122, 4695-4700).
  def test_a_drop_reaches_the_window_holding_the_webview
    run_app { [N::DragDropEvent.new("side", "leave", [], 0, 0)] }

    assert_includes log, [:listener, "second", W::DragDrop]
    assert_includes log, [:run, "second", W::DragDrop]
    refute_includes log, [:builder, "main", W::DragDrop]
  end

  def test_a_drop_follows_the_webview_to_its_new_window
    run_app(on_ready: -> (handle) { handle.webviews["side"].window = handle.windows["main"] }) do
      [N::DragDropEvent.new("side", "leave", [], 0, 0)]
    end

    assert_includes log, [:builder, "main", W::DragDrop]
    refute_includes log, [:listener, "second", W::DragDrop]
  end

  def test_a_webviews_focus_is_its_windows
    run_app { [N::WebviewFocusedEvent.new("side", true)] }

    assert_includes log, [:listener, "second", W::Focused]
    assert_includes log, [:run, "second", W::Focused]
    refute_includes log, [:builder, "main", W::Focused]
  end

  # On Windows the theme goes to that window's webviews
  # (tauri-runtime-wry lib.rs:4153-4166).
  def test_a_theme_change_themes_only_its_windows_webviews
    run_app(native: ThemedNative) { [N::WindowThemeChangedEvent.new("second", "dark")] }

    assert_equal [[:set_theme, "side", "Dark"]], log.select { |entry| entry[0] == :set_theme }
  end

  def test_closing_a_window_asks_the_loop_to_close_that_window
    run_app(on_ready: -> (handle) { handle.windows["second"].close }) { [] }

    assert_includes log, [:run, "second", W::CloseRequested]
    assert_predicate native_window("second"), :closed?
    refute_predicate native_window("main"), :closed?
  end

  # Both labels reach the page as serde_json writes them
  # (manager/webview.rs:177-188).
  def test_the_metadata_script_writes_each_label_as_json
    app = run_app { [] }

    assert(native_webview("main").initialization_scripts.any? { |script|
      script.include?('currentWindow: { label: "main" }') && script.include?('currentWebview: { label: "main" }')
    })
    script = app.handle.webview_manager.metadata_script(%(a"b), "c\\d")
    assert_includes script, 'currentWindow: { label: "a\"b" }'
    assert_includes script, 'currentWebview: { label: "c\\\\d" }'
  end

  private def log
    Thread.current[:routing]
  end

  # Builds the app with "second" and "side", queues the events the block
  # answers for it, and runs it, logging the run events by window label.
  private def run_app(native: StubNative, builder: nil, invoke: false, plugin: false, on_ready: nil)
    Thread.current[:routing_native] = native
    configured = Tokra::Builder.default.setup(&SECOND).on_window_event(&BUILDER_LISTENER)
    configured = configured.invoke_handler(&WHOAMI) if invoke
    configured = builder.call(configured) if builder
    app = build_test_app(configured, native:)
    if plugin
      app.handle.plugin(PageLoadPlugin.new(app.handle))
      app.handle.plugin(LaterPageLoadPlugin.new(app.handle))
    end
    StubNative.inject_event(yield(app))
    app.run do |handle, event|
      case event
      when Tokra::RunEvent::Ready then on_ready&.call(handle)
      when Tokra::RunEvent::ExitRequested then log << [:exit_requested]
      when Tokra::RunEvent::WindowEvent
        log << [:run, event.label, event.event.class]
        log << [:size, event.label, event.event.size] if event.event.is_a?(W::Resized)
        if event.event.is_a?(W::Destroyed)
          log << [:manager, event.label, handle.windows.keys, handle.webviews.keys]
        end
      end
    end
    app
  rescue SystemExit
    app
  end

  private def native_window(label)
    StubNative.windows.find { |window| window.label == label }
  end

  private def native_webview(label)
    StubNative::WebView.instances.find { |webview| webview.label == label }
  end

  private def ipc_event(app, label)
    message = { "cmd" => "whoami", "callback" => 1, "error" => 2, "__TAURI_INVOKE_KEY__" => app.invoke_key }
    N::IpcEvent.new(label, JSON.generate(message), LocalOrigin.url(app:))
  end

  private def ipc_request(label, method: "POST", key: "")
    headers = [
      ["content-type", "application/json"],
      ["tauri-callback", "1"],
      ["tauri-error", "2"],
      ["tauri-invoke-key", key],
      ["origin", LocalOrigin.url("")],
    ]
    N::HttpRequestEvent.new(label:, request_id: 7, method:, uri: "ipc://localhost/whoami", headers:, body: "{}")
  end

  private def tokra_request(label)
    N::HttpRequestEvent.new(label:, request_id: 8, method: "GET", uri: "tokra://localhost/", headers: [], body: "")
  end
end
