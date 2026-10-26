# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/autorun"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"
require "fileutils"
require "tokra-dialog"

# Tokra's StubNative double lives with the core tests; plugins exercise a
# real AppHandle built on it instead of a hand-rolled stand-in.
$LOAD_PATH.unshift File.expand_path("../../../../test", __dir__)
require "support/stub_native"

# Helpers every dialog test shares: a real app handle, invokes that record
# their answer, and a child Ruby for tests that open a real dialog.
module DialogTest
  Dialog = Tokra::Plugins::Dialog

  # The platform ferro-rfd's extension was built for, as rfd's cfg decides.
  PLATFORM = Ferro::Rfd.const_get(:PLATFORM)

  # This plugin's lib directory, for child processes.
  LIB = File.expand_path("../../lib", __dir__)

  # How long a child may run before it is killed, in seconds.
  CHILD_LIMIT = 30

  private def skip_unless_platform(platform)
    skip "#{platform} only; ferro-rfd was built for #{PLATFORM}" unless PLATFORM == platform
  end

  # A real app handle, built exactly as an app builds one.
  private def build_app
    Tokra::Builder.default.build(native: StubNative)
  end

  # A registered plugin on a real handle.
  private def build_plugin(app = build_app)
    plugin = Dialog::Plugin.new(app.handle)
    app.handle.plugin(plugin)
    plugin
  end

  # The Dialog a registered plugin manages.
  private def new_dialog
    app = build_app
    build_plugin(app)
    app.handle.dialog
  end

  # The calling webview and its window, as the App would pass them.
  private def stub_webview(handle)
    window = Tokra::Window.new(label: "main", native: Object.new, app_handle: handle)
    Tokra::Webview.new(label: "main", native: Object.new, window:, app_handle: handle)
  end

  # An invoke whose answers land in the returned Queue as
  # <tt>[success, value]</tt>.
  private def build_invoke(handle, command, payload = {})
    answers = Thread::Queue.new
    invoke = Tokra::Ipc::Invoke.new(
      command:,
      payload:,
      webview: stub_webview(handle),
      responder: -> (success, json) { answers << [success, JSON.parse(json)] }
    )
    [invoke, answers]
  end

  # Runs +command+ with +payload+ through the plugin and returns the first
  # answer, or +nil+ when none came within a second.
  private def answer(command, payload = {})
    app = build_app
    plugin = build_plugin(app)
    invoke, answers = build_invoke(app.handle, command, payload)
    handled = plugin.extend_api(invoke)
    assert handled, "the plugin should claim #{command}"
    answers.pop(timeout: 1)
  end

  # Runs +command+ through the plugin while this thread plays the event
  # loop for RuntimeContext, running each task the command sends to the
  # main thread, and returns the answer, or +nil+ after five seconds.
  private def pumped_answer(command, payload)
    app = build_app
    plugin = build_plugin(app)
    invoke, answers = build_invoke(app.handle, command, payload)
    plugin.extend_api(invoke)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    until Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      app.handle.runtime_context.handle_task
      answer = answers.pop(timeout: 0.01)
      return answer if answer
    end
    nil
  end

  # The rejection message for +command+ with +payload+.
  private def rejection(command, payload)
    success, value = answer(command, payload)
    refute success, "#{command} #{payload.inspect} should reject, but resolved #{value.inspect}"
    value
  end

  # Runs +script+ in a fresh Ruby with the plugin loaded, with +env+ added
  # to its environment, and returns the value its last expression
  # marshals to standard output, and its standard error. A child that
  # outlives CHILD_LIMIT is killed and the test fails.
  private def in_child(script, env = {})
    child = <<~RUBY
      require "tokra-dialog"
      $LOAD_PATH.unshift #{File.expand_path('../../../../test', __dir__).dump}
      require "support/stub_native"
      value = eval(#{script.dump}, TOPLEVEL_BINDING)
      $stdout.binmode.write(Marshal.dump(value))
    RUBY
    Open3.popen3(env, RbConfig.ruby, "-I", LIB, "-e", child) do |stdin, stdout, stderr, thread|
      stdin.close
      output = Thread.new { stdout.binmode.read }
      errors = Thread.new { stderr.read }
      unless thread.join(CHILD_LIMIT)
        Process.kill(:KILL, thread.pid)
        flunk "the child Ruby ran past #{CHILD_LIMIT} s and was killed: #{errors.value}"
      end
      raise "the child Ruby failed: #{errors.value}" unless thread.value.success?

      [Marshal.load(output.value), errors.value]
    end
  end

  # Ruby for a child: runs +command+ with +payload+ through the plugin on a
  # real handle whose event loop is this thread. The test thread takes the
  # loop's part for RuntimeContext, running each task the plugin sends to
  # the main thread, until the invoke answers. Evaluates to
  # <tt>[success, value]</tt>.
  CHILD_COMMAND = <<~RUBY
    def run_command(command, payload)
      app = Tokra::Builder.default.build(native: StubNative)
      handle = app.handle
      plugin = Tokra::Plugins::Dialog::Plugin.new(handle)
      handle.plugin(plugin)
      window = Tokra::Window.new(label: "main", native: Object.new, app_handle: handle)
      webview = Tokra::Webview.new(label: "main", native: Object.new, window:, app_handle: handle)
      answers = Thread::Queue.new
      invoke = Tokra::Ipc::Invoke.new(command:, payload:, webview:,
        responder: ->(success, json) { answers << [success, JSON.parse(json)] })
      plugin.extend_api(invoke)
      context = handle.runtime_context
      loop do
        context.handle_task
        answer = answers.pop(timeout: 0.01)
        return answer if answer
      end
    end
  RUBY
end
