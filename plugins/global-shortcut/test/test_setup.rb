# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/global_shortcut_test"

# The Builder and the plugin's setup (lib.rs:336-435). A plugin makes a
# hotkey manager, and macOS allows one at a time, so each test that sets up
# a plugin does it in a child process of its own.
class TestSetup < Minitest::Test
  include GlobalShortcutTest

  def setup
    RealWindowsRun.require!("a hotkey registered for the whole desktop")
  end

  # The child's app handle, as an app builds one.
  PRELUDE = <<~RUBY
    HANDLE = TestApp.build_test_app.handle
    def event(shortcut, state)
      G::ShortcutEvent.new(G::Shortcut.from_str(shortcut).id, state)
    end
  RUBY

  def test_the_builders_shortcuts_are_registered_at_setup_and_hear_its_handler
    results, = in_display_child(PRELUDE + <<~RUBY)
      heard = []
      builder = G::Builder.new
        .with_shortcut(#{child_unusual('F17').dump})
        .with_shortcuts([#{child_unusual('F18').dump}])
        .with_handler { |app, shortcut, event| heard << [app.equal?(HANDLE), shortcut.to_s, event.state.debug] }
      plugin = builder.build
      HANDLE.plugin(plugin)
      shortcuts = HANDLE.global_shortcut
      registered = [shortcuts.is_registered(#{child_unusual('F17').dump}), shortcuts.is_registered(#{child_unusual('F18').dump})]
      shortcuts.handle_event(event(#{child_unusual('F18').dump}, G::ShortcutState::Pressed), builder.handler)
      shortcuts.unregister_all
      [registered, plugin.name, HANDLE.global_shortcut.class.name, heard]
    RUBY

    registered, name, managed, heard = results
    assert_equal [true, true], registered
    assert_equal "global-shortcut", name
    assert_equal "Tokra::Plugins::GlobalShortcut::GlobalShortcut", managed
    assert_equal [[true, "control+alt+meta+F18", "Pressed"]], heard
  end

  def test_a_shortcut_that_does_not_parse_fails_the_builder
    error = assert_raises(G::Error::GlobalHotkey) { G::Builder.new.with_shortcuts([unusual, "ctrl+bogus"]) }
    assert_match(/\ACouldn't recognize "bogus"/, error.message)
    assert_raises(ArgumentError) { G::Builder.new.with_handler }
  end

  # Builder#plugin takes the plugin before the app exists, and App#run runs
  # its setup, which registers the builder's shortcuts and manages the
  # GlobalShortcut; a page with withGlobalTauri runs Tauri's api-iife.js
  # after Tauri's bundle (plan 064).
  def test_builder_plugin_sets_up_at_run_and_the_page_runs_the_global_api_script
    path = File.expand_path("../lib/tokra/plugins/global_shortcut/api-iife.js", __dir__)
    (registered, order), = in_display_child(<<~RUBY)
      builder = Tokra::Builder.default.plugin(G::Builder.new.with_shortcut(#{child_unusual('F17').dump}).build)
      app = TestApp.build_test_app(builder, config: { "app" => { "withGlobalTauri" => true } })
      app.run
      registered = app.handle.global_shortcut.is_registered(#{child_unusual('F17').dump})
      app.handle.global_shortcut.unregister_all
      scripts = app.handle.webviews["main"].native.initialization_scripts
      [registered, [scripts.index(File.read(#{path.dump})), scripts.index { |each| each.include?("__TAURI_IIFE__") }]]
    RUBY

    assert registered, "the builder's shortcut is registered when the app runs"
    script, bundle = order
    refute_nil script, "the page runs the plugin's global API script"
    assert_operator script, :>, bundle, "after Tauri's bundle, whose window.__TAURI__ it extends"
  end

  # Setup's ? (lib.rs:399-410) fails the plugin's initialization with
  # global-hotkey's message (plugin.rs:1009).
  def test_a_shortcut_the_system_refuses_fails_setup
    shortcut, message = unsupported
    (failure, managed), = in_display_child(PRELUDE + <<~RUBY)
      begin
        HANDLE.plugin(G::Builder.new.with_shortcuts([#{child_unusual('F17').dump}, #{shortcut.dump}]).build)
        nil
      rescue Tokra::Error::PluginInitialization => e
        [[e.class.name, e.plugin, e.message], HANDLE.try_state(G::GlobalShortcut)]
      end
    RUBY

    assert_equal [
      "Tokra::Error::PluginInitialization",
      "global-shortcut",
      "failed to initialize plugin `global-shortcut`: #{message}",
], failure
    assert_nil managed, "a failed setup manages nothing"
  end

  # Carbon installs global-hotkey's handler once, so a second manager fails
  # while the first lives (Ferro's plan 004, decision 3).
  def test_macos_keeps_one_plugin_per_process
    skip_unless_platform(:macos)
    failure, = in_child(PRELUDE + <<~RUBY)
      HANDLE.plugin(G::Builder.new.build)
      begin
        HANDLE.plugin(G::Builder.new.build)
        nil
      rescue Tokra::Error::PluginInitialization => e
        e.message
      end
    RUBY

    assert_match(/\Afailed to initialize plugin `global-shortcut`: .*\(os error \d+\)\z/, failure)
  end
end
