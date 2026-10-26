# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/global_shortcut_test"

# The plugin's commands (lib.rs:268-334) through extend_api on the shared
# plugin, from a webview whose native webview records what the page would
# evaluate.
class TestCommands < Minitest::Test
  include GlobalShortcutTest

  def setup
    @webview = recording_webview(shared.handle)
  end

  def teardown
    shared.global_shortcut.unregister_all
  end

  private def call(command, payload = {})
    answer(command, payload, webview: @webview)
  end

  private def evals
    @webview.native.evals
  end

  private def event(shortcut, state)
    shared.global_shortcut.handle_event(G::ShortcutEvent.new(G::Shortcut.from_str(shortcut).id, state), nil)
  end

  def test_the_plugin_is_named_and_claims_only_its_commands
    assert_equal "global-shortcut", shared.plugin.name
    invoke, = build_invoke(@webview, "register_multiple")
    refute shared.plugin.extend_api(invoke), "Tokra rejects the rest with Command NAME not found"
  end

  def test_register_then_is_registered_then_unregister
    assert_equal [true, nil], call("register", { "shortcuts" => [unusual], "handler" => "__CHANNEL__:7" })
    assert_equal [true, true], call("is_registered", { "shortcut" => unusual })
    assert_equal [true, false], call("is_registered", { "shortcut" => unusual("F18") })

    assert_equal [true, nil], call("unregister", { "shortcuts" => [unusual] })
    assert_equal [true, false], call("is_registered", { "shortcut" => unusual })
  end

  # ShortcutJsEvent (lib.rs:268-273, 294-301): the shortcut's own text, the
  # id, and the state, in that order, each at the next index.
  def test_each_event_reaches_the_page_through_its_channel
    call("register", { "shortcuts" => [unusual], "handler" => "__CHANNEL__:7" })
    event(unusual, G::ShortcutState::Pressed)
    event(unusual, G::ShortcutState::Released)

    id = G::Shortcut.from_str(unusual).id
    assert_equal [
      %(window.__TAURI_INTERNALS__.runCallback(7, { message: {"shortcut":"shift+control+alt+meta+F19","id":#{id},"state":"Pressed"}, index: 0 })),
      %(window.__TAURI_INTERNALS__.runCallback(7, { message: {"shortcut":"shift+control+alt+meta+F19","id":#{id},"state":"Released"}, index: 1 })),
    ], evals.grep(/runCallback\(7,/)
  end

  # The command's closure owns the Channel; Rust drops it, and the page
  # hears the end, when the last of its shortcuts goes (channel.rs:186-193).
  def test_the_channel_ends_when_its_last_shortcut_is_unregistered
    call("register", { "shortcuts" => [unusual("F17"), unusual("F18")], "handler" => "__CHANNEL__:8" })
    call("unregister", { "shortcuts" => [unusual("F17")] })
    assert_empty evals.grep(/runCallback\(8, \{ end/), "a shortcut still holds the channel"

    call("unregister", { "shortcuts" => [unusual("F18")] })
    assert_equal ["window.__TAURI_INTERNALS__.runCallback(8, { end: true, index: 0 })"], evals.grep(/runCallback\(8,/)
  end

  def test_registering_nothing_ends_the_channel_at_once
    assert_equal [true, nil], call("register", { "shortcuts" => [], "handler" => "__CHANNEL__:13" })
    assert_equal ["window.__TAURI_INTERNALS__.runCallback(13, { end: true, index: 0 })"], evals
  end

  # The handler ignores a channel that can no longer send, as Tauri's
  # let _ = does (lib.rs:300).
  def test_an_event_after_the_loop_ends_is_dropped_quietly
    handle = Tokra::Builder.default.build(native: StubNative).handle
    webview = recording_webview(handle)
    channel = Tokra::Ipc::Channel.from_command(build_invoke(webview, "register", { "handler" => "__CHANNEL__:14" }).first, "handler")
    handle.runtime_context.close
    handler = G::Commands::ChannelHandler.new(channel)

    assert_silent do
      Thread.new { handler.call(handle, G::Shortcut.from_str(unusual), G::ShortcutEvent.new(1, G::ShortcutState::Pressed)) }.join
    end
    assert_empty webview.native.evals
  end

  def test_unregister_all_ends_every_channel
    call("register", { "shortcuts" => [unusual("F17")], "handler" => "__CHANNEL__:9" })
    call("register", { "shortcuts" => [unusual("F18")], "handler" => "__CHANNEL__:10" })

    assert_equal [true, nil], call("unregister_all")
    assert_equal [true, false], call("is_registered", { "shortcut" => unusual("F17") })
    assert_equal [
      "window.__TAURI_INTERNALS__.runCallback(10, { end: true, index: 0 })",
      "window.__TAURI_INTERNALS__.runCallback(9, { end: true, index: 0 })",
], evals.grep(/end: true/).sort
  end

  # A shortcut that does not parse rejects with global-hotkey's message
  # (error.rs:18-37), and the Channel the command took is dropped.
  def test_a_shortcut_that_does_not_parse_rejects_and_ends_the_channel
    assert_equal [
      false,
      "Couldn't recognize \"bogus\" as a valid key for hotkey, if you feel like it should be, " \
        "please report this to https://github.com/tauri-apps/muda",
],
      call("register", { "shortcuts" => [unusual, "ctrl+bogus"], "handler" => "__CHANNEL__:11" })
    assert_equal ["window.__TAURI_INTERNALS__.runCallback(11, { end: true, index: 0 })"], evals
    assert_equal [true, false], call("is_registered", { "shortcut" => unusual }), "nothing is registered"
  end

  def test_a_shortcut_the_system_refuses_rejects_with_its_message
    shortcut, message = unsupported
    assert_equal [false, message], call("register", { "shortcuts" => [shortcut], "handler" => "__CHANNEL__:12" })
    assert_equal ["window.__TAURI_INTERNALS__.runCallback(12, { end: true, index: 0 })"], evals
  end

  # Unlike GlobalShortcut#is_registered, the command rejects a string that
  # does not parse (lib.rs:327-334).
  def test_is_registered_rejects_a_shortcut_that_does_not_parse
    assert_match(/\ACouldn't recognize "bogus"/, rejection("is_registered", { "shortcut" => "bogus" }))
    assert_match(/\ACouldn't recognize "bogus"/, rejection("unregister", { "shortcuts" => ["bogus"] }))
  end

  # serde's messages, through Tauri's InvalidArgs (error.rs:59-60), in the
  # order the arguments are read: shortcuts, then the handler.
  def test_bad_arguments_reject_with_tauris_messages
    assert_equal "invalid args `shortcuts` for command `register`: command register missing required key shortcuts",
      rejection("register", { "handler" => "__CHANNEL__:1" })
    assert_equal "invalid args `shortcuts` for command `register`: invalid type: string \"F19\", expected a sequence",
      rejection("register", { "shortcuts" => "F19" })
    assert_equal "invalid args `shortcuts` for command `register`: invalid type: integer `1`, expected a string",
      rejection("register", { "shortcuts" => [1] })
    assert_equal "invalid args `handler` for command `register`: command register missing required key handler",
      rejection("register", { "shortcuts" => [unusual] })
    assert_equal "invalid channel value `7`, expected a string in the `__CHANNEL__:ID` format",
      rejection("register", { "shortcuts" => [unusual], "handler" => "7" })
    assert_equal "invalid args `shortcuts` for command `unregister`: invalid type: null, expected a sequence",
      rejection("unregister", { "shortcuts" => nil })
    assert_equal "invalid args `shortcut` for command `is_registered`: invalid type: floating point `1.5`, expected a string",
      rejection("is_registered", { "shortcut" => 1.5 })
    assert_equal [true, false], call("is_registered", { "shortcut" => unusual }), "nothing was registered"
  end
end
