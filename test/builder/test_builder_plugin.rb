# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/local_origin"
require_relative "../support/stub_native"
require_relative "../support/test_app"

# Tests how an app registers and initializes its plugins (plan 064).
#
# Tauri's Builder::plugin puts a plugin in the builder's store unread;
# Builder::build registers the core plugins after it and, last,
# initializes every plugin with its slice of config.plugins
# (app.rs:1701-1713, 2247, 2289; plugin.rs:906-915, 999-1010).
# AppHandle::plugin initializes a plugin at once and registers it only if
# that worked (app.rs:485-498).
class TestBuilderPlugin < Minitest::Test
  # Reads a plugin's config as any JSON value, as a Rust plugin whose
  # config type is serde_json::Value does.
  module AnyConfig
    def self.deserialize(value) = value
  end

  # Records what a plugin's setup saw, in order, across the plugins of a
  # test.
  class Log
    attr_reader :entries

    def initialize
      @entries = []
    end

    def <<(entry)
      @entries << entry
      self
    end
  end

  def teardown
    StubNative.clear_event
  end

  def test_builder_plugin_is_initialized_by_run_with_its_config
    seen = nil
    plugin = Tokra::Plugin::Builder.new("example", config: AnyConfig)
      .setup { |app, api| seen = [app, api.app, api.name, api.config] }
      .build
    app = build_test_app(Tokra::Builder.default.plugin(plugin),
      config: { "plugins" => { "example" => { "answer" => 42 } } })

    assert_nil seen, "Builder#plugin only stores the plugin; setup waits for the app"
    app.run

    assert_equal [app.handle, app.handle, "example", { "answer" => 42 }], seen
  end

  def test_a_missing_slice_is_null
    seen = :unset
    plugin = Tokra::Plugin::Builder.new("example", config: AnyConfig).setup { |_app, api| seen = api.config }.build
    build_test_app(Tokra::Builder.default.plugin(plugin)).run

    assert_nil seen, "config.0.get(name).unwrap_or_default() is JSON null (plugin.rs:1007)"
  end

  def test_a_unit_config_refuses_a_map_with_tauris_words
    plugin = Tokra::Plugin::Builder.new("example").setup { |_app, _api| flunk "setup must not run" }.build
    app = build_test_app(Tokra::Builder.default.plugin(plugin), config: { "plugins" => { "example" => {} } })

    error = assert_raises(Tokra::Error::PluginInitialization) { app.run }

    assert_equal "failed to initialize plugin `example`: Error deserializing 'plugins.example' within your " \
      "Tokra configuration: invalid type: map, expected unit", error.message
    assert_equal "example", error.plugin
  end

  def test_a_unit_config_takes_null
    seen = :unset
    plugin = Tokra::Plugin::Builder.new("example").setup { |_app, api| seen = api.config }.build
    build_test_app(Tokra::Builder.default.plugin(plugin), config: { "plugins" => { "example" => nil } }).run

    assert_nil seen
  end

  def test_a_plugin_without_setup_never_reads_its_config
    plugin = Tokra::Plugin::Builder.new("example").build
    app = build_test_app(Tokra::Builder.default.plugin(plugin), config: { "plugins" => { "example" => [1] } })

    app.run # Tauri deserializes only inside `if let Some(s) = self.setup.take()` (plugin.rs:793-806)
  end

  def test_a_failing_setup_ends_run_with_plugin_initialization
    plugin = Tokra::Plugin::Builder.new("example").setup { |_app, _api| raise "no device" }.build
    app = build_test_app(Tokra::Builder.default.plugin(plugin))

    error = assert_raises(Tokra::Error::PluginInitialization) { app.run }

    assert_equal "failed to initialize plugin `example`: no device", error.message
    assert_empty StubNative.event_loop_calls.select { |call| call == [:run] }, "the loop never runs"
  end

  def test_plugins_initialize_before_the_config_windows_and_the_setup_hook
    log = Log.new
    plugin = Tokra::Plugin::Builder.new("example")
      .setup { |app, _api| log << [:plugin_setup, app.windows.keys] }
      .on_window_ready { |window| log << [:window_ready, window.label] }
      .build
    builder = Tokra::Builder.default.plugin(plugin).setup(&Ractor.shareable_proc { |_app| Thread.current[:hook] = true })
    Thread.current[:hook] = nil
    app = build_test_app(builder)

    app.run

    assert_equal [[:plugin_setup, []], [:window_ready, "main"]], log.entries,
      "Builder::build initializes plugins before setup builds the config windows (app.rs:2289, 2370-2384)"
    assert Thread.current[:hook]
  ensure
    Thread.current[:hook] = nil
  end

  def test_builder_plugins_come_before_the_core_plugins
    plugin = Tokra::Plugin::Builder.new("example").js_init_script("window.example = 1").build
    app = build_test_app(Tokra::Builder.default.plugin(plugin))
    scripts = app.handle.manager.plugins.initialization_script.map(&:first)

    assert_equal "(function () { window.example = 1 })();", scripts[0],
      "the builder's store holds its plugins before register_core_plugins adds the rest (app.rs:2094-2104, 2247)"
    assert_includes scripts[1], "window.__TAURI_INTERNALS__.plugins, 'path'",
      "then the core plugins, the path plugin first (app.rs:1122-1124)"
  end

  def test_a_later_builder_plugin_replaces_a_same_named_one
    log = Log.new
    first = Tokra::Plugin::Builder.new("example").setup { |_app, _api| log << :first }.on_drop { |_app| log << :drop }.build
    second = Tokra::Plugin::Builder.new("example").setup { |_app, _api| log << :second }.build

    build_test_app(Tokra::Builder.default.plugin(first).plugin(second)).run

    assert_equal [:second], log.entries,
      "no error for a duplicate; the first, never initialized, drops without on_drop (plugin.rs:774-780, 880-886)"
  end

  def test_initialize_all_skips_a_plugin_the_handle_already_initialized
    log = Log.new
    plugin = Tokra::Plugin::Builder.new("example").setup { |_app, _api| log << :setup }.build
    other = Class.new(Tokra::Plugin) do
      define_method(:name) { "other" }
      define_method(:initialize_plugin) do |app, config|
        log << :other
        super(app, config)
      end
    end.new
    app = build_test_app(Tokra::Builder.default.plugin(plugin))
    app.handle.plugin(other)

    app.run

    assert_equal %i[other setup], log.entries, "each plugin is initialized once"
  end

  def test_app_handle_plugin_initializes_at_once_with_its_slice
    seen = nil
    plugin = Tokra::Plugin::Builder.new("example", config: AnyConfig).setup { |_app, api| seen = api.config }.build
    app = build_test_app(config: { "plugins" => { "example" => "on" } })

    assert_nil app.handle.plugin(plugin), "AppHandle::plugin returns Result<()> (app.rs:485-498)"

    assert_equal "on", seen
    assert app.handle.remove_plugin("example"), "it is registered"
  end

  def test_app_handle_plugin_that_fails_is_not_registered_and_drops
    dropped = nil
    plugin = Tokra::Plugin::Builder.new("example")
      .setup { |_app, _api| raise ArgumentError, "bad" }
      .on_drop { |app| dropped = app }
      .build
    app = build_test_app

    error = assert_raises(Tokra::Error::PluginInitialization) { app.handle.plugin(plugin) }

    assert_equal "failed to initialize plugin `example`: bad", error.message
    refute app.handle.remove_plugin("example"), "store.register is never reached (app.rs:496)"
    assert_same app.handle, dropped, "the plugin had its app, so its Drop ran on_drop"
  end

  def test_remove_plugin_drops_an_initialized_plugin_once
    dropped = []
    plugin = Tokra::Plugin::Builder.new("example").on_drop { |app| dropped << app }.build
    app = build_test_app
    app.handle.plugin(plugin)

    app.handle.remove_plugin("example")
    plugin.drop

    assert_equal [app.handle], dropped, "on_drop is an FnOnce, taken as it runs (plugin.rs:774-780)"
  end

  def test_replacing_a_plugin_through_the_handle_drops_the_old_one
    log = Log.new
    first = Tokra::Plugin::Builder.new("example").on_drop { |_app| log << :first_dropped }.build
    second = Tokra::Plugin::Builder.new("example").setup { |_app, _api| log << :second_setup }.build
    app = build_test_app
    app.handle.plugin(first)

    app.handle.plugin(second)

    assert_equal %i[second_setup first_dropped], log.entries,
      "the new plugin initializes, then register drops the old (app.rs:496-497; plugin.rs:880-886)"
  end

  def test_a_tauri_plugin_answers_its_invokes_through_the_router
    plugin = Tokra::Plugin::Builder.new("example")
      .invoke_handler do |invoke|
        next false unless invoke.command == "greet"

        invoke.resolve("hi #{invoke.payload['name']}")
        true
      end
      .build
    app = build_test_app(Tokra::Builder.default.plugin(plugin))
    StubNative.inject_event([
      ipc_event(app, "plugin:example|greet", { "name" => "Ada" }, 1),
      ipc_event(app, "plugin:example|nope", {}, 3),
    ])

    app.run

    evals = app.handle.webviews["main"].native.evals
    assert(evals.any? { |script| script.include?("runCallback(1, ") && script.include?('"hi Ada"') }, evals.inspect)
    assert(evals.any? { |script| script.include?("runCallback(4, ") && script.include?("Command nope not found") },
      "an invoke the handler leaves is not found (webview/mod.rs on_message)")
  end

  def test_a_tauri_plugin_hears_its_lifecycle_hooks
    log = Log.new
    plugin = Tokra::Plugin::Builder.new("example")
      .on_webview_ready { |webview| log << [:webview, webview.label] }
      .on_page_load { |webview, payload| log << [:page, webview.label, payload.url.as_str, payload.finished?] }
      .on_event { |_app, event| log << [:event, event.class] }
      .build
    app = build_test_app(Tokra::Builder.default.plugin(plugin))
    StubNative.inject_event(Tokra::Native::PageLoadEvent.new("main", "finished", "tokra://localhost/"))

    app.run

    assert_equal [
      [:webview, "main"],
      [:event, Tokra::RunEvent::Ready],
      [:page, "main", "tokra://localhost/", true],
      [:event, Tokra::RunEvent::Exit],
    ], log.entries
  end

  def test_js_init_script_runs_in_the_main_frame_and_on_all_frames_everywhere
    main = Tokra::Plugin::Builder.new("main-only").js_init_script("window.a = 1").build
    all = Tokra::Plugin::Builder.new("all").js_init_script("ignored").js_init_script_on_all_frames("window.b = 2").build
    app = build_test_app(Tokra::Builder.default.plugin(main).plugin(all))

    app.run

    pairs = app.handle.webviews["main"].native.initialization_script_pairs
    assert_includes pairs, ["(function () { window.a = 1 })();", true]
    assert_includes pairs, ["(function () { window.b = 2 })();", false],
      "a later call replaces the script and its frames (plugin.rs:368-405)"
  end

  private def ipc_event(app, cmd, payload, callback)
    Tokra::Native::IpcEvent.new("main", JSON.generate(
      "cmd" => cmd, "callback" => callback, "error" => callback + 1, "payload" => payload,
      "__TAURI_INVOKE_KEY__" => app.invoke_key
    ), LocalOrigin.url)
  end
end
