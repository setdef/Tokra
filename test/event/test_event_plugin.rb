# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/stub_native"
require_relative "../support/test_app"

# The event core plugin's commands, which @tauri-apps/api/event calls
# (event/plugin.rs, packages/api/src/event.ts), and its init script
# (event/init.js).
class TestEventPlugin < Minitest::Test
  T = Tokra::EventTarget

  def setup
    @app = build_test_app
    @handle = @app.handle
    @native_webview = StubNative::WebView.new
    window = Tokra::Window.new(label: "main", native: StubNative::Window.new(nil, "main"), app_handle: @handle)
    @webview = Tokra::Webview.new(label: "main", native: @native_webview, window:, app_handle: @handle)
    @handle.windows["main"] = window
    @handle.webviews["main"] = @webview
  end

  def test_the_plugin_is_a_core_plugin_with_tauris_init_script
    script = @handle.manager.plugins.initialization_script.find { |s| s.include?("__TAURI_EVENT_PLUGIN_INTERNALS__") }

    refute_nil script
    assert_includes script, "unregisterListener: (event, eventId) => (function () {\n"
    assert_includes script, "const listeners = (window['__internal_unstable_listeners_object_id__'] || {})[event]"
    assert_includes script, "window.__TAURI_INTERNALS__.unregisterCallback(listeners[eventId].handlerId)"
  end

  def test_listen_registers_in_the_page_then_answers_the_id
    answer = invoke("listen", { "event" => "a", "target" => { "kind" => "Window", "label" => "main" }, "handler" => 77 })

    assert_equal [true, "0"], answer
    assert_includes @native_webview.evals.first, "handlerId: 77"
    @handle.emit_to(T.window("main"), "a", 5)
    assert @native_webview.evals.last.end_with?("payload: 5}, [0]) })()"), @native_webview.evals.last
  end

  def test_unlisten_forgets_the_page_listener
    invoke("listen", { "event" => "a", "target" => { "kind" => "Any" }, "handler" => 1 })
    evals = @native_webview.evals.length

    assert_equal [true, "null"], invoke("unlisten", { "event" => "a", "eventId" => 0 })
    @handle.emit("a", 1)

    assert_equal evals, @native_webview.evals.length, "no webview listens for the event any more"
  end

  def test_emit_reaches_ruby
    heard = []
    @handle.listen("a") { |event| heard << event.payload }

    assert_equal [true, "null"], invoke("emit", { "event" => "a", "payload" => { "x" => [1] } })
    assert_equal [true, "null"], invoke("emit", { "event" => "a" })

    assert_equal ['{"x":[1]}', "null"], heard
  end

  def test_emit_to_reaches_the_target
    heard = []
    @handle.listen("a") { heard << :app }
    @webview.listen("a") { heard << :webview }

    assert_equal [true, "null"], invoke("emit_to", { "target" => { "kind" => "Webview", "label" => "main" }, "event" => "a" })

    assert_equal [:webview], heard
  end

  # The command macro reads arguments in order, and the first that fails
  # rejects the invoke (event/plugin.rs:14-58).
  def test_arguments_are_read_in_order
    {
      ["listen", { "event" => "a b", "target" => 1 }] =>
        "invalid args `event` for command `listen`: Event name must include only alphanumeric characters, `-`, `/`, `:` and `_`.",
      ["listen", { "event" => "a", "target" => { "kind" => "App" } }] =>
        "invalid args `handler` for command `listen`: command listen missing required key handler",
      ["listen", { "event" => "a", "target" => {} }] =>
        "invalid args `target` for command `listen`: missing field `kind`",
      ["listen", { "event" => "a", "target" => { "kind" => "App" }, "handler" => -1 }] =>
        "invalid args `handler` for command `listen`: invalid value: integer `-1`, expected u32",
      ["unlisten", { "event" => "a", "eventId" => "x" }] =>
        "invalid args `eventId` for command `unlisten`: invalid type: string \"x\", expected u32",
      ["emit", { "payload" => 1 }] => "invalid args `event` for command `emit`: command emit missing required key event",
      ["emit_to", { "event" => "a" }] => "invalid args `target` for command `emit_to`: command emit_to missing required key target",
    }.each do |(command, payload), message|
      assert_equal [false, JSON.generate(message)], invoke(command, payload), command
    end
  end

  def test_other_commands_are_not_the_plugins
    refute @handle.manager.plugins.extend_api("event", request("nope", {}) { nil })
  end

  private def invoke(command, payload)
    answer = nil
    handled = @handle.manager.plugins.extend_api("event", request(command, payload) { |success, json| answer = [success, json] })
    assert handled, command
    answer
  end

  private def request(command, payload, &responder)
    Tokra::Ipc::Invoke.new(command:, payload:, headers: {}, responder:, webview: @webview)
  end
end
