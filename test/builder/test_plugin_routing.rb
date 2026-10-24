# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/stub_native"

# Tests for IPC routing of plugin:NAME|command invokes.
#
# Mirrors Tauri webview/mod.rs: commands prefixed with "plugin:" route to
# the named plugin's extend_api hook with the bare command name; all other
# commands go to the app's invoke_handler. Messages carry the app's
# invoke key (ipc/protocol.rs Message); arguments ride in the payload
# member.
class TestBuilderPluginRouting < Minitest::Test
  # Named plugin recording extend_api calls.
  class RecordingPlugin < Tokra::Plugin
    attr_reader :invokes

    def initialize(app = nil, config = {}, handles: true)
      super(app, config)
      @handles = handles
      @invokes = []
    end

    def name = "recording"

    def extend_api(invoke)
      @invokes << invoke
      @handles
    end
  end

  private def inject_ipc(app, message)
    StubNative.inject_event(Tokra::Native::IpcEvent.new(
      JSON.generate(message.merge("__TAURI_INVOKE_KEY__" => app.invoke_key)),
      "tokra://localhost/"
    ))
  end

  def test_plugin_command_routes_with_bare_command
    plugin = RecordingPlugin.new
    app = Tokra::Builder.default.build(native: StubNative)
    app.handle.plugin(plugin)
    inject_ipc(app, "cmd" => "plugin:recording|greet", "payload" => { "text" => "Hello" })

    app.run

    assert_equal 1, plugin.invokes.size, "registered plugin should receive the invoke"
    invoke = plugin.invokes.first
    assert_equal "greet", invoke.command,
      "plugin should receive the bare command, not the plugin:-prefixed string"
    assert_equal "Hello", invoke.payload["text"], "payload member should pass through"
  ensure
    StubNative.clear_event
  end

  def test_plugin_command_without_separator_has_empty_command
    plugin = RecordingPlugin.new
    app = Tokra::Builder.default.build(native: StubNative)
    app.handle.plugin(plugin)
    inject_ipc(app, "cmd" => "plugin:recording")

    app.run

    assert_equal "", plugin.invokes.first.command,
      "missing | separator should yield an empty command like Tauri"
  ensure
    StubNative.clear_event
  end

  def test_plugin_command_does_not_reach_invoke_handler
    Thread.current[:handler_called] = false
    handler = Ractor.shareable_proc { |_invoke| Thread.current[:handler_called] = true }
    app = Tokra::Builder.default.invoke_handler(&handler).build(native: StubNative)
    app.handle.plugin(RecordingPlugin.new)
    inject_ipc(app, "cmd" => "plugin:recording|greet")

    app.run

    refute Thread.current[:handler_called],
      "plugin commands should route to the plugin store, not the app invoke_handler"
  ensure
    StubNative.clear_event
  end

  def test_unhandled_plugin_command_is_rejected
    plugin = RecordingPlugin.new(handles: false)
    app = Tokra::Builder.default.build(native: StubNative)
    app.handle.plugin(plugin)
    inject_ipc(app, "cmd" => "plugin:recording|nope")

    app.run

    invoke = plugin.invokes.first
    assert invoke.instance_variable_get(:@responded),
      "dispatcher should reject a plugin command no handler claimed"
  ensure
    StubNative.clear_event
  end

  def test_unhandled_app_command_is_rejected
    Thread.current[:test_invoke] = nil
    handler = Ractor.shareable_proc { |invoke|
      Thread.current[:test_invoke] = invoke
      false
    }
    app = Tokra::Builder.default.invoke_handler(&handler).build(native: StubNative)
    inject_ipc(app, "cmd" => "unknown")

    app.run

    invoke = Thread.current[:test_invoke]
    assert invoke.instance_variable_get(:@responded),
      "dispatcher should reject an app command the invoke_handler did not claim"
  ensure
    StubNative.clear_event
  end

  def test_core_image_plugin_is_registered_automatically
    app = Tokra::Builder.default.build(native: StubNative)
    inject_ipc(app,
      "cmd" => "plugin:image|new",
      "payload" => { "rgba" => [255, 0, 0, 255], "width" => 1, "height" => 1 })

    app.run

    entries = app.handle.webviews["main"].resources_table.names.to_a
    assert_equal 1, entries.size, "plugin:image|new should store an image without user setup"
    assert_equal "Tokra::Image", entries.first[1]
  ensure
    StubNative.clear_event
  end

  def test_core_resources_plugin_is_registered_automatically
    app = Tokra::Builder.default.build(native: StubNative)
    rid = app.handle.resources_table.add(Tokra::Image.new(rgba: "", width: 0, height: 0))
    inject_ipc(app, "cmd" => "plugin:resources|close", "payload" => { "rid" => rid })

    app.run

    refute app.handle.resources_table.has?(rid),
      "plugin:resources|close should close app-level resources without user setup"
  ensure
    StubNative.clear_event
  end
end
