# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

# The plugin's two commands, sent by the page through a real app's IPC
# router, and the exit and restart they ask the real AppHandle for.
#
# Mirrors tauri-plugin-process at plugins-workspace d4613ff0: lib.rs:19-23
# names the plugin and its handler, and commands.rs:7-15 calls
# AppHandle::exit(code) and AppHandle::request_restart().
class TestCommands < Minitest::Test
  include ProcessTest

  # Builder::new("process") (lib.rs:20), the name in
  # <tt>plugin:process|exit</tt>.
  def test_the_plugin_is_named_process
    app = build_app

    assert_equal "process", Tokra::Plugins::Process::Plugin.new(app.handle).name
    assert app.handle.remove_plugin("process"), "the plugin registers under its name"
  end

  # exit(code) calls AppHandle::exit (commands.rs:7-10), which asks the
  # loop: handlers hear ExitRequested with the code, and the loop ends
  # with it. The command returns (), so the page's promise resolves null.
  def test_exit_asks_the_app_to_exit_with_the_code
    app = build_app
    send_invoke(app, "plugin:process|exit", { "code" => 3 })

    run_app(app)

    assert_equal [3], exit_codes
    assert_equal [Tokra::RunEvent::ExitRequested, Tokra::RunEvent::Exit], exit_kinds
    assert_equal 3, StubNative.exit_code, "the loop ends with the page's code"
    assert_equal [resolved("null")], answers(app)
  end

  # AppHandle::exit asks rather than ends (app.rs:531-538), so a handler
  # that prevents the exit keeps the app running.
  def test_a_handler_can_prevent_the_exit_the_page_asked_for
    app = build_app
    send_invoke(app, "plugin:process|exit", { "code" => 3 })

    run_app(app) { |_handle, event| event.api.prevent_exit if event.is_a?(Tokra::RunEvent::ExitRequested) }

    assert_equal [3], exit_codes
    assert_nil StubNative.exit_code, "the prevented request does not end the loop"
    assert_equal [resolved("null")], answers(app)
  end

  # The page's exit() sends code 0 when given none (guest-js/index.ts:25).
  def test_exit_with_the_pages_default_code_ends_with_zero
    app = build_app
    send_invoke(app, "plugin:process|exit", { "code" => 0 })

    run_app(app)

    assert_equal [0], exit_codes
    assert_equal 0, StubNative.exit_code
  end

  # code is an i32: both ends of its range read.
  def test_exit_takes_both_ends_of_the_i32_range
    [-(2 ** 31), (2 ** 31) - 1].each do |code|
      StubNative.clear_event
      @events = []
      app = build_app
      send_invoke(app, "plugin:process|exit", { "code" => code })

      run_app(app)

      assert_equal [code], exit_codes
    end
  end

  # The #[tauri::command] macro reads code with serde, and a missing key
  # rejects with Tauri's message (ipc/command.rs:97-102, error.rs:59-60)
  # before the command runs.
  def test_exit_without_a_code_rejects_and_does_not_exit
    app = build_app
    send_invoke(app, "plugin:process|exit", {})

    _, stderr = capture_io { run_app(app) }

    assert_empty stderr, "the page's mistake is no failed command to report"
    assert_empty exit_codes
    assert_equal [rejected("invalid args `code` for command `exit`: command exit missing required key code")],
      answers(app)
  end

  # A code that is not an i32 rejects with serde's message
  # (ipc/command.rs:60-70; serde's primitive visitors).
  def test_exit_with_a_code_that_is_not_an_i32_rejects_and_does_not_exit
    {
      "1" => "invalid type: string \"1\", expected i32",
      1.5 => "invalid type: floating point `1.5`, expected i32",
      nil => "invalid type: null, expected i32",
      true => "invalid type: boolean `true`, expected i32",
      2 ** 31 => "invalid value: integer `2147483648`, expected i32",
      -(2 ** 31) - 1 => "invalid value: integer `-2147483649`, expected i32",
    }.each do |code, reason|
      StubNative.clear_event
      @events = []
      app = build_app
      send_invoke(app, "plugin:process|exit", { "code" => code })

      run_app(app)

      assert_empty exit_codes, code.inspect
      assert_equal [rejected("invalid args `code` for command `exit`: #{reason}")], answers(app), code.inspect
    end
  end

  # restart calls AppHandle::request_restart (commands.rs:12-15): the loop
  # hears ExitRequested with RESTART_EXIT_CODE, which no handler can
  # prevent, then Exit, and then the app's command line runs again and
  # this process exits 0 (app.rs:572-582, process.rs:73-87).
  def test_restart_asks_the_app_to_restart_after_its_exit
    app = build_app
    send_invoke(app, "plugin:process|restart")

    exit = run_app_until_restart(app) do |_handle, event|
      event.api.prevent_exit if event.is_a?(Tokra::RunEvent::ExitRequested)
    end

    assert_equal [Tokra::RESTART_EXIT_CODE], exit_codes
    assert_equal [Tokra::RunEvent::ExitRequested, Tokra::RunEvent::Exit, :spawn], exit_kinds
    binary = Tokra::Process.current_binary(app.handle.env)
    assert_equal [[[binary, binary], *ENV_FOR_TESTS.args_os.drop(1)]], @spawned, "the same script and arguments"
    assert_equal 0, exit.status
    assert_equal [resolved("null")], answers(app), "the page hears back before the loop ends"
  end

  # The restart command reads no argument, so whatever the page sends
  # does not stop it.
  def test_restart_ignores_its_payload
    app = build_app
    send_invoke(app, "plugin:process|restart", { "code" => "not a number" })

    run_app_until_restart(app)

    assert_equal [Tokra::RESTART_EXIT_CODE], exit_codes
    assert_equal [resolved("null")], answers(app)
  end

  # generate_handler! names only exit and restart (lib.rs:21); the router
  # rejects any other command of the plugin.
  def test_other_commands_are_not_found
    %w[relaunch kill exit_code].each do |command|
      StubNative.clear_event
      app = build_app
      send_invoke(app, "plugin:process|#{command}", { "code" => 1 })

      run_app(app)

      assert_equal [rejected("Command #{command} not found")], answers(app), command
    end
    assert_empty exit_codes
  end
end
