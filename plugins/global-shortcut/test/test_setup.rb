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

  # The child's app handle, as an app builds one.
  PRELUDE = <<~RUBY
    HANDLE = Tokra::Builder.default.build(native: StubNative).handle
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
        .with_handler { |app, shortcut, event| heard << [app.equal?(HANDLE), shortcut.to_s, event.state.inspect] }
      plugin = builder.build(HANDLE)
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
    assert_equal [[true, "control+alt+meta+F18", "Ferro::GlobalHotkey::HotKeyState::Pressed"]], heard
  end

  def test_a_shortcut_that_does_not_parse_fails_the_builder
    error = assert_raises(G::Error::GlobalHotkey) { G::Builder.new.with_shortcuts([unusual, "ctrl+bogus"]) }
    assert_match(/\ACouldn't recognize "bogus"/, error.message)
    assert_raises(ArgumentError) { G::Builder.new.with_handler }
  end

  # Setup's ? (lib.rs:399-410) fails the plugin's initialization with
  # global-hotkey's message (plugin.rs:1009).
  def test_a_shortcut_the_system_refuses_fails_setup
    shortcut, message = unsupported
    (failure, managed), = in_display_child(PRELUDE + <<~RUBY)
      begin
        G::Builder.new.with_shortcuts([#{child_unusual('F17').dump}, #{shortcut.dump}]).build(HANDLE)
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
      HANDLE.plugin(G::Plugin.new(HANDLE))
      begin
        G::Plugin.new(HANDLE)
        nil
      rescue Tokra::Error::PluginInitialization => e
        e.message
      end
    RUBY

    assert_match(/\Afailed to initialize plugin `global-shortcut`: .*\(os error \d+\)\z/, failure)
  end
end
