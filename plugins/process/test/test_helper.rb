# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/autorun"
require "minitest/mock"
require "json"
require "rbconfig"
require "tokra-process"

# Tokra's StubNative double lives with the core tests; the plugin's tests
# run a real App and AppHandle built on it instead of a hand-rolled
# stand-in.
$LOAD_PATH.unshift File.expand_path("../../../test", __dir__)
require "support/stub_native"
require "support/test_app"
require "support/local_origin"

# A real app with the process plugin registered, run over StubNative, and
# the page's invokes sent through the app's own IPC router.
module ProcessTest
  # The command line the test apps restart with. A test run's own $0 may
  # be "-e", which a restart refuses (Plan 039, decision 10).
  ENV_FOR_TESTS = Tokra::Env.new(args_os: [RbConfig.ruby, __FILE__, "two words"].freeze)

  # The callback and error ids the page's invoke carries.
  CALLBACK = 1
  ERROR = 2

  def setup
    StubNative.clear_event
    @events = []
    @spawned = []
  end

  def teardown
    StubNative.clear_event
  end

  # A real app, its Env the command line above, with the plugin
  # registered on its builder as the README shows.
  private def build_app
    builder = Tokra::Builder.default.plugin(Tokra::Plugins::Process.init)
    Tokra::Env.stub(:default, ENV_FOR_TESTS) { build_test_app(builder) }
  end

  # Queues the page's invoke of +cmd+ with +payload+, from the app's own
  # origin, as the page's IPC message reaches the loop.
  private def send_invoke(app, cmd, payload = {})
    message = {
      "cmd" => cmd,
      "callback" => CALLBACK,
      "error" => ERROR,
      "payload" => payload,
      "__TAURI_INVOKE_KEY__" => app.invoke_key,
    }
    StubNative.inject_event(Tokra::Native::IpcEvent.new("main", JSON.generate(message), LocalOrigin.url(app:)))
  end

  # Runs +app+ until its loop ends, recording each run event and calling
  # +reaction+ with the handle and the event. An exit that ends the
  # process instead, as Kernel.exit would, fails the test rather than
  # ending the test run.
  private def run_app(app, &reaction)
    app.run { |handle, event| record(handle, event, reaction) }
  rescue SystemExit => e
    flunk "the app ended the process with status #{e.status} instead of ending its loop"
  end

  # Runs +app+ until it restarts, as #run_app does, with Ruby's
  # Process.spawn recording its arguments as an event, so no second
  # process starts. Returns the SystemExit that ends the restarting
  # process.
  private def run_app_until_restart(app, &reaction)
    spawn = lambda do |*command|
      @spawned << command
      @events << :spawn
      4242
    end
    ::Process.stub(:spawn, spawn) do
      assert_raises(SystemExit) { app.run { |handle, event| record(handle, event, reaction) } }
    end
  end

  private def record(handle, event, reaction)
    @events << event
    reaction&.call(handle, event)
  end

  # The kinds of the run events, and :spawn, in order, from the first
  # ExitRequested on.
  private def exit_kinds
    kinds = @events.map { |event| event.is_a?(Symbol) ? event : event.class }
    kinds.drop_while { |kind| kind != Tokra::RunEvent::ExitRequested }
  end

  # The codes of the ExitRequested events.
  private def exit_codes
    @events.grep(Tokra::RunEvent::ExitRequested).map(&:code)
  end

  # The scripts the app evaluated in the calling page: the invoke's
  # answer.
  private def answers(app)
    app.handle.webviews["main"].native.evals
  end

  # The page's callback script for a resolution with +json+.
  private def resolved(json)
    "window.__TAURI_INTERNALS__.runCallback(#{CALLBACK}, #{json})"
  end

  # The page's callback script for a rejection with +message+.
  private def rejected(message)
    "window.__TAURI_INTERNALS__.runCallback(#{ERROR}, #{JSON.generate(message)})"
  end
end
