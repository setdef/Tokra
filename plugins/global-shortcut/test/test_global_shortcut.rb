# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/global_shortcut_test"

# GlobalShortcut's Ruby API (lib.rs:129-242) on the shared plugin, with real
# shortcuts registered with the system and unregistered after each test.
class TestGlobalShortcut < Minitest::Test
  include GlobalShortcutTest

  def setup
    @shortcuts = shared.global_shortcut
  end

  def teardown
    @shortcuts&.unregister_all
  end

  def test_a_registered_shortcut_is_registered_until_unregistered
    assert_nil @shortcuts.register(unusual)
    assert @shortcuts.is_registered(unusual)
    assert @shortcuts.is_registered(G::Shortcut.from_str(unusual)), "a Shortcut and its string are the same shortcut"
    refute @shortcuts.is_registered(unusual("F18"))

    assert_nil @shortcuts.unregister(unusual)
    refute @shortcuts.is_registered(unusual)
  end

  def test_a_shortcut_value_registers_as_its_string_does
    modifiers = G::Modifiers
    shortcut = G::Shortcut.new(modifiers::CONTROL | modifiers::ALT | modifiers::SHIFT | modifiers::META, G::Code::F18)
    @shortcuts.register(shortcut)

    assert @shortcuts.is_registered(unusual("F18"))
  end

  def test_several_register_and_unregister_together
    @shortcuts.register_multiple([unusual("F17"), unusual("F18")])
    assert(%w[F17 F18].all? { |key| @shortcuts.is_registered(unusual(key)) })

    @shortcuts.unregister_multiple([unusual("F17"), unusual("F18")])
    refute(%w[F17 F18].any? { |key| @shortcuts.is_registered(unusual(key)) })
  end

  def test_unregister_all_forgets_every_shortcut
    @shortcuts.register(unusual("F17"))
    @shortcuts.on_shortcut(unusual("F18")) { nil }
    assert_nil @shortcuts.unregister_all

    refute @shortcuts.is_registered(unusual("F17"))
    refute @shortcuts.is_registered(unusual("F18"))
  end

  # try_into_shortcut (lib.rs:258-266): the parse error's own message.
  def test_a_shortcut_that_does_not_parse_raises_global_hotkeys_message
    error = assert_raises(G::Error::GlobalHotkey) { @shortcuts.register("ctrl+bogus") }
    assert_equal "Couldn't recognize \"bogus\" as a valid key for hotkey, if you feel like it should be, " \
      "please report this to https://github.com/tauri-apps/muda", error.message
    assert_raises(G::Error::GlobalHotkey) { @shortcuts.unregister("") }
    refute @shortcuts.is_registered("ctrl+bogus"), "is_registered answers false for a string that does not parse"
    assert_raises(TypeError) { @shortcuts.register(19) }
  end

  def test_a_key_the_system_lacks_raises_its_message
    shortcut, message = unsupported
    error = assert_raises(G::Error::GlobalHotkey) { @shortcuts.register(shortcut) }

    assert_equal message, error.message
    refute @shortcuts.is_registered(shortcut), "a refused shortcut is not stored"
  end

  # A second registration of the same combination: Carbon refuses it on
  # macOS; Windows and Linux report AlreadyRegistered (Ferro's
  # test_manager.rb).
  def test_registering_twice_raises_the_systems_refusal
    @shortcuts.register(unusual)
    error = assert_raises(G::Error::GlobalHotkey) { @shortcuts.register(unusual) }

    if PLATFORM == :macos
      assert_equal "Unable to register hotkey: RegisterEventHotKey failed for F19", error.message
    else
      assert_match(/\AHotKey already registered: HotKey \{ mods: Modifiers\(/, error.message)
    end
    assert @shortcuts.is_registered(unusual), "the first registration stays"
  end

  def test_on_shortcuts_gives_each_shortcut_the_one_handler
    keys = []
    @shortcuts.on_shortcuts([unusual("F17"), G::Shortcut.from_str(unusual("F18"))]) { |_app, shortcut, _event| keys << shortcut.key }
    %w[F17 F18].each do |key|
      @shortcuts.handle_event(G::ShortcutEvent.new(G::Shortcut.from_str(unusual(key)).id, G::ShortcutState::Pressed), nil)
    end

    assert_equal [G::Code::F17, G::Code::F18], keys
  end

  def test_handlers_need_a_block
    assert_raises(ArgumentError) { @shortcuts.on_shortcut(unusual) }
    assert_raises(ArgumentError) { @shortcuts.on_shortcuts([unusual]) }
  end

  # The event handler's body (lib.rs:416-425): the shortcut's own handler,
  # then the builder's, each with the app handle, the Shortcut, and the
  # event.
  def test_an_event_calls_the_shortcuts_handler_then_the_global_one
    calls = []
    @shortcuts.on_shortcut(unusual) { |app, shortcut, event| calls << [:own, app, shortcut.to_s, event.state] }
    global = -> (app, shortcut, event) { calls << [:global, app, shortcut.to_s, event.state] }
    id = G::Shortcut.from_str(unusual).id

    @shortcuts.handle_event(G::ShortcutEvent.new(id, G::ShortcutState::Pressed), global)
    @shortcuts.handle_event(G::ShortcutEvent.new(id + 1, G::ShortcutState::Pressed), global)

    text = G::Shortcut.from_str(unusual).to_s
    assert_equal [[:own, shared.handle, text, G::ShortcutState::Pressed], [:global, shared.handle, text, G::ShortcutState::Pressed]],
      calls
  end

  def test_a_shortcut_without_its_own_handler_still_reaches_the_global_one
    calls = []
    @shortcuts.register_multiple([unusual("F17"), unusual("F18")])
    @shortcuts.handle_event(G::ShortcutEvent.new(G::Shortcut.from_str(unusual("F18")).id, G::ShortcutState::Released),
      -> (_app, shortcut, event) { calls << [shortcut.key, event.state] })

    assert_equal [[G::Code::F18, G::ShortcutState::Released]], calls
  end

  def test_an_unregistered_shortcut_calls_no_handler
    calls = []
    @shortcuts.on_shortcut(unusual) { calls << :own }
    @shortcuts.unregister(unusual)
    @shortcuts.handle_event(G::ShortcutEvent.new(G::Shortcut.from_str(unusual).id, G::ShortcutState::Pressed), -> (*) { calls << :global })

    assert_empty calls
  end

  def test_a_handler_that_raises_is_reported_and_the_next_still_runs
    calls = []
    @shortcuts.on_shortcut(unusual) { raise "boom" }
    id = G::Shortcut.from_str(unusual).id

    _, err = capture_io do
      @shortcuts.handle_event(G::ShortcutEvent.new(id, G::ShortcutState::Pressed), -> (*) { calls << :global })
    end

    assert_equal [:global], calls
    assert_match(/global shortcut handler failed: .*boom/, err)
  end

  # A handler may call the plugin, where Tauri's lock deadlocks (Plan 025,
  # decision 6).
  def test_a_handler_may_unregister_its_own_shortcut
    @shortcuts.on_shortcut(unusual) { |app, shortcut, _event| app.global_shortcut.unregister(shortcut) }
    @shortcuts.handle_event(G::ShortcutEvent.new(G::Shortcut.from_str(unusual).id, G::ShortcutState::Pressed), nil)

    refute @shortcuts.is_registered(unusual)
  end

  # run_main_thread! (lib.rs:75-86): a call from another thread waits for
  # the main thread to run it.
  def test_a_call_from_another_thread_runs_when_the_main_thread_does
    context = shared.handle.runtime_context
    context.attach(StubNative::Proxy.new)
    caller = Thread.new { @shortcuts.register(unusual) }
    Thread.pass until context.instance_variable_get(:@tasks).any? || !caller.alive?
    refute @shortcuts.is_registered(unusual), "the call waits for the main thread"

    context.handle_task
    caller.join(5)
    assert @shortcuts.is_registered(unusual)
  end

  # Tauri's ? turns a closed loop's errors into Error::Tauri and
  # Error::RecvError (error.rs:12-15).
  def test_after_the_loop_ends_calls_from_another_thread_raise_tauris_errors
    handle = Tokra::Builder.default.build(native: StubNative).handle
    shortcuts = G::GlobalShortcut.new(handle, shared.global_shortcut.instance_variable_get(:@manager), {})
    context = handle.runtime_context

    waiting = quiet_thread { shortcuts.register(unusual) }
    Thread.pass until context.instance_variable_get(:@tasks).any?
    context.close
    recv = assert_raises(G::Error::RecvError) { waiting.join }
    assert_equal "receiving on a closed channel", recv.message

    tauri = assert_raises(G::Error::Tauri) { quiet_thread { shortcuts.register(unusual) }.join }
    assert_equal "runtime error: failed to send message to the webview", tauri.message
    refute shortcuts.is_registered(unusual)
  end

  # unregister_all forgets the shortcuts before it asks the main thread, so
  # their handlers drop even when it cannot (lib.rs:219-227).
  def test_unregister_all_drops_the_handlers_when_the_loop_has_ended
    handle = Tokra::Builder.default.build(native: StubNative).handle
    dropped = Thread::Queue.new
    channel = Tokra::Ipc::Channel.new_with_id(1, -> (_json) {}, -> { dropped << :dropped })
    shortcut = G::Shortcut.from_str(unusual)
    entry = G::GlobalShortcut::RegisteredShortcut.new(shortcut:, handler: G::Commands::ChannelHandler.new(channel))
    shortcuts = G::GlobalShortcut.new(handle, shared.global_shortcut.instance_variable_get(:@manager), { shortcut.id => entry })
    handle.runtime_context.close

    assert_raises(G::Error::Tauri) { quiet_thread { shortcuts.unregister_all }.join }
    assert_equal :dropped, dropped.pop(timeout: 1)
    refute shortcuts.is_registered(unusual)
  end

  # A thread whose exception the test reads from join, not stderr.
  private def quiet_thread(&)
    Thread.new do
      Thread.current.report_on_exception = false
      yield
    end
  end
end
