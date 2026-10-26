# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/global_shortcut_test"

# Real shortcut events on Linux: a child process sets up the plugin on the
# suite's private X server, xdotool presses the keys there, and
# global-hotkey's X11 thread reports the press and the release to the
# handler the plugin installed (lib.rs:416-425). Each runs in a child of
# its own, as global-hotkey's handler is set once per process.
class TestLinuxEvents < Minitest::Test
  include GlobalShortcutTest

  # The child's app handle and a way to press keys on the private server.
  PRELUDE = <<~RUBY
    HANDLE = Tokra::Builder.default.build(native: StubNative).handle
    def press(keys)
      system("xdotool", "key", "--delay", "100", keys) or raise "xdotool failed"
    end
  RUBY

  def setup
    skip_unless_platform(:linux)
    require_x_server
  end

  def test_a_press_reaches_the_shortcuts_handler_then_the_builders_on_another_thread
    heard, = in_display_child(PRELUDE + <<~RUBY)
      heard = Thread::Queue.new
      plugin = G::Builder.new
        .with_handler { |_app, shortcut, event| heard << [:global, shortcut.to_s, event.state.inspect] }
        .build(HANDLE)
      HANDLE.plugin(plugin)
      HANDLE.global_shortcut.on_shortcut("ctrl+alt+shift+F24") do |app, shortcut, event|
        heard << [:own, shortcut.to_s, event.state.inspect, app.equal?(HANDLE), Thread.current == Thread.main]
      end
      press("ctrl+alt+shift+F24")
      events = Array.new(4) { heard.pop(timeout: 10) }
      HANDLE.global_shortcut.unregister_all
      events
    RUBY

    pressed = "Ferro::GlobalHotkey::HotKeyState::Pressed"
    released = "Ferro::GlobalHotkey::HotKeyState::Released"
    assert_equal [
      [:own, "shift+control+alt+F24", pressed, true, false],
      [:global, "shift+control+alt+F24", pressed],
      [:own, "shift+control+alt+F24", released, true, false],
      [:global, "shift+control+alt+F24", released],
    ], heard
  end

  # The register command's Channel carries each event to the page
  # (lib.rs:293-302).
  def test_a_press_reaches_the_page_through_the_register_commands_channel
    evals, = in_display_child(PRELUDE + <<~RUBY)
      HANDLE.plugin(plugin = G::Plugin.new(HANDLE))
      window = Tokra::Window.new(label: "main", native: Object.new, app_handle: HANDLE)
      webview = Tokra::Webview.new(label: "main", native: StubNative::WebView.new, window:, app_handle: HANDLE)
      answers = Thread::Queue.new
      invoke = Tokra::Ipc::Invoke.new(command: "register", webview:,
        payload: { "shortcuts" => ["ctrl+alt+shift+F24"], "handler" => "__CHANNEL__:21" },
        responder: -> (success, json) { answers << [success, json] })
      plugin.extend_api(invoke)
      raise "register failed: \#{answers.pop.inspect}" unless answers.pop == [true, "null"]

      # The page's eval travels to the main thread, which here runs no loop,
      # so the test waits for the queued tasks and runs them itself.
      context = HANDLE.runtime_context
      context.attach(StubNative::Proxy.new)
      press("ctrl+alt+shift+F24")
      deadline = Time.now + 10
      until webview.native.evals.size >= 2 || Time.now > deadline
        context.handle_task
        sleep 0.05
      end
      HANDLE.global_shortcut.unregister_all
      context.handle_task
      webview.native.evals
    RUBY

    id = G::Shortcut.from_str("ctrl+alt+shift+F24").id
    assert_equal [
      %(window.__TAURI_INTERNALS__.runCallback(21, { message: {"shortcut":"shift+control+alt+F24","id":#{id},"state":"Pressed"}, index: 0 })),
      %(window.__TAURI_INTERNALS__.runCallback(21, { message: {"shortcut":"shift+control+alt+F24","id":#{id},"state":"Released"}, index: 1 })),
      "window.__TAURI_INTERNALS__.runCallback(21, { end: true, index: 2 })",
    ], evals
  end

  # global-hotkey keeps the first handler set in the process
  # (lib.rs:118-124), so a second plugin's shortcuts reach no handler, as in
  # Tauri.
  def test_only_the_first_plugin_in_a_process_hears_its_shortcuts
    heard, = in_display_child(PRELUDE + <<~RUBY)
      heard = Thread::Queue.new
      second = Tokra::Builder.default.build(native: StubNative).handle
      HANDLE.plugin(G::Plugin.new(HANDLE))
      second.plugin(G::Plugin.new(second))
      second.global_shortcut.on_shortcut("ctrl+alt+shift+F17") { |*| heard << :second }
      HANDLE.global_shortcut.on_shortcut("ctrl+alt+shift+F24") { |_app, _shortcut, event| heard << :first }
      press("ctrl+alt+shift+F17")
      press("ctrl+alt+shift+F24")
      events = Array.new(2) { heard.pop(timeout: 10) }
      sleep 0.3
      events << heard.size
      [HANDLE, second].each { |handle| handle.global_shortcut.unregister_all }
      events
    RUBY

    assert_equal [:first, :first, 0], heard
  end

  def test_an_unregistered_shortcut_reaches_no_handler
    heard, = in_display_child(PRELUDE + <<~RUBY)
      heard = Thread::Queue.new
      HANDLE.plugin(G::Plugin.new(HANDLE))
      HANDLE.global_shortcut.on_shortcut("ctrl+alt+shift+F24") { |*| heard << :heard }
      HANDLE.global_shortcut.unregister("ctrl+alt+shift+F24")
      press("ctrl+alt+shift+F24")
      sleep 0.5
      heard.size
    RUBY

    assert_equal 0, heard
  end
end
