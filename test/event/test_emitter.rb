# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/stub_native"
require_relative "../support/test_app"

# Listener and Emitter on App, AppHandle, Window, and Webview (lib.rs:829-1048,
# app.rs:1055-1112, window/mod.rs:2235-2310, webview/mod.rs:2180-2255), and
# the manager's emit, emit_filter, and emit_to (manager/mod.rs:500-635).
class TestEventEmitter < Minitest::Test
  T = Tokra::EventTarget

  def setup
    StubNative::WebView.instances.clear
    @app = build_test_app
    @handle = @app.handle
    @native_webview = StubNative::WebView.new
    @window = Tokra::Window.new(label: "main", native: StubNative::Window.new(nil, "main"), app_handle: @handle)
    @webview = Tokra::Webview.new(label: "main", native: @native_webview, window: @window, app_handle: @handle)
    @handle.windows["main"] = @window
    @handle.webviews["main"] = @webview
    @heard = []
  end

  def test_emit_reaches_every_listener
    listen_everywhere("a")

    @handle.emit("a", { "n" => 1 })

    assert_equal [[:app, '{"n":1}'], [:handle, '{"n":1}'], [:window, '{"n":1}'], [:webview, '{"n":1}'], [:any, '{"n":1}']],
      @heard.map { |who, event| [who, event.payload] }
  end

  def test_each_listener_gets_its_own_id
    ids = listen_everywhere("a")

    @window.emit("a", nil)

    assert_equal ids, @heard.map { |_, event| event.id }
  end

  # emit_to's filter_target (manager/mod.rs:597-628).
  def test_emit_to_matches_targets_as_tauri_does
    listen_everywhere("a")
    @handle.listen_any("a") { |event| @heard << [:any_again, event] }

    expectations = {
      T.any => %i[app handle window webview any any_again],
      T.app => %i[app handle any any_again],
      T.window("main") => %i[window any any_again],
      T.webview("main") => %i[webview any any_again],
      T.webview_window("main") => %i[any any_again],
      T.labeled("main") => %i[window webview any any_again],
      "main" => %i[window webview any any_again],
      T.window("other") => %i[any any_again],
    }
    expectations.each do |target, heard|
      @heard.clear
      @app.emit_to(target, "a", 1)
      assert_equal heard, @heard.map(&:first), target.inspect
    end
  end

  def test_emit_filter_asks_the_block
    listen_everywhere("a")

    @webview.emit_filter("a", 1) { |target| target.is_a?(T::Window) }

    assert_equal %i[window any], @heard.map(&:first)
  end

  # Tauri's emit_filter takes the filter as an argument (lib.rs:1025-1034).
  def test_emit_filter_needs_its_block
    assert_raises(ArgumentError) { @handle.emit_filter("a", 1) }
    assert_raises(ArgumentError) { @handle.emit_str_filter("a", "1") }
  end

  def test_once_and_unlisten
    @handle.once("a") { |event| @heard << [:once, event] }
    id = @window.listen("a") { |event| @heard << [:window, event] }
    @window.unlisten(id)
    @webview.once_any("a") { |event| @heard << [:once_any, event] }

    @handle.emit("a", 1)
    @handle.emit("a", 2)

    assert_equal [[:once, "1"], [:once_any, "1"]], @heard.map { |who, event| [who, event.payload] }
  end

  def test_names_are_checked_before_anything_happens
    %i[listen once listen_any once_any].each do |method|
      assert_raises(Tokra::Error::IllegalEventName, method) { @handle.public_send(method, "a b") { nil } }
    end
    assert_raises(Tokra::Error::IllegalEventName) { @window.emit("a b", 1) }
    assert_raises(Tokra::Error::IllegalEventName) { @webview.emit_to(T.any, "a b", 1) }
    assert_raises(Tokra::Error::IllegalEventName) { @app.emit_filter("a b", 1) { true } }
  end

  def test_payloads_serialize_as_serde_json_writes_them
    @handle.listen_any("a") { |event| @heard << [:any, event] }

    @handle.emit("a", { "f" => 1.0, "nan" => Float::NAN, "list" => [1, "x", nil] })
    @handle.emit_str("a", "raw text")
    @handle.emit_str_to(T.any, "a", "[1]")
    @handle.emit_str_filter("a", "{}") { true }

    assert_equal ['{"f":1.0,"nan":null,"list":[1,"x",null]}', "raw text", "[1]", "{}"],
      @heard.map { |_, event| event.payload }
  end

  # AppManager::emit evaluates in the webviews, then calls Ruby's handlers
  # (manager/mod.rs:544-547), with Tauri's emit script and the ids of the
  # page's listeners (event/mod.rs:190-202, listener.rs:270-297).
  def test_emit_reaches_the_page_before_ruby
    id = @webview.listen_js("a", T.any, 42)
    @handle.listen_any("a") { @heard << [:ruby, @native_webview.evals.dup] }

    @handle.emit("a", { "x" => 1 })

    script = "(function () { const fn = window['__internal_unstable_listeners_function_id__']; " \
      "fn && fn({event: 'a', payload: {\"x\":1}}, [#{id}]) })()"
    assert_equal script, @native_webview.evals.last
    assert_includes @heard.first.last, script, "the page heard it before the Ruby handler ran"
  end

  def test_emit_to_sends_the_page_only_the_ids_whose_target_matches
    any = @webview.listen_js("a", T.any, 1)
    window = @webview.listen_js("a", T.window("main"), 2)
    @webview.listen_js("a", T.app, 3)

    @handle.emit_to(T.window("main"), "a", nil)

    assert @native_webview.evals.last.end_with?(", [#{any},#{window}]) })()"), @native_webview.evals.last
  end

  # listen_js evaluates Tauri's listen script before recording the
  # listener (webview/mod.rs:1904-1927; event/mod.rs:164-188).
  def test_listen_js_registers_the_listener_in_the_page
    id = @webview.listen_js("tauri://resize", T.window("main"), 9)

    script = @native_webview.evals.last
    assert_includes script, "window['__internal_unstable_listeners_object_id__']['tauri://resize']"
    assert_includes script, "target: {\"kind\":\"Window\",\"label\":\"main\"},\n        handlerId: 9"
    assert_includes script, "Object.defineProperty(eventListeners, '#{id}', { value: listener, configurable: true });"
  end

  private def listen_everywhere(name)
    [
      @app.listen(name) { |event| @heard << [:app, event] },
      @handle.listen(name) { |event| @heard << [:handle, event] },
      @window.listen(name) { |event| @heard << [:window, event] },
      @webview.listen(name) { |event| @heard << [:webview, event] },
      @window.listen_any(name) { |event| @heard << [:any, event] },
    ]
  end
end
