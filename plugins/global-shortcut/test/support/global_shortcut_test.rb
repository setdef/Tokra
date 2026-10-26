# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/autorun"
require "json"
require "open3"
require "rbconfig"
require "tokra-global-shortcut"

# Tokra's StubNative double lives with the core tests; plugins exercise a
# real AppHandle built on it instead of a hand-rolled stand-in.
$LOAD_PATH.unshift File.expand_path("../../../../test", __dir__)
require "support/stub_native"

# Helpers every global-shortcut test shares.
#
# A registered shortcut belongs to the whole desktop while it is
# registered, and an event needs a key press, so these tests take care with
# both:
#
# - They register only combinations nobody uses, Control, Alt (Option),
#   Shift, and Meta (Command, Windows) with F17 to F19 or F24, and always
#   unregister them.
# - On Linux, everything that talks to X runs against a private Xvfb the
#   suite starts (XServer), never the desktop's display, so the keys
#   xdotool presses and the keymap changes reach nothing of the user's.
# - macOS allows one hotkey manager at a time, and global-hotkey's event
#   handler is set once per process, so the test process shares one app and
#   plugin (GlobalShortcutTest.shared), and tests that need a plugin of
#   their own run in a child process (#in_child).
module GlobalShortcutTest
  G = Tokra::Plugins::GlobalShortcut

  # The platform ferro-global-hotkey's extension was built for.
  PLATFORM = Ferro::GlobalHotkey.const_get(:PLATFORM)

  # This plugin's lib directory, for child processes.
  LIB = File.expand_path("../../lib", __dir__)

  # How long a child may run before it is killed, in seconds.
  CHILD_LIMIT = 40

  # The app and plugin the test process shares, made once.
  class Shared < Data.define(:app, :plugin)
    def handle = app.handle
    def global_shortcut = handle.global_shortcut
  end

  class << self
    # The shared app and plugin, made on first use on the main thread. On
    # Linux the manager connects to the private X server, so the caller
    # must have called require_x_server first.
    def shared
      @shared ||= begin
        app = Tokra::Builder.default.build(native: StubNative)
        plugin = G::Plugin.new(app.handle)
        app.handle.plugin(plugin)
        Shared.new(app:, plugin:)
      end
    end
  end

  # A combination nobody uses: Control, Alt, Shift, and Meta with +key+.
  private def unusual(key = "F19")
    "ctrl+alt+shift+super+#{key}"
  end

  # Another combination nobody uses, Control, Alt, and Meta with +key+,
  # for the children. On Linux the X server keeps a grab until the manager
  # that let it go next asks it something (Ferro's plan 004), so the
  # children never grab what the test process has grabbed.
  private def child_unusual(key)
    "ctrl+alt+super+#{key}"
  end

  # A key this platform has no code for, which global-hotkey refuses to
  # register (Ferro's test_manager.rb), and its message.
  private def unsupported
    case PLATFORM
    when :macos then [unusual("F24"), "Unable to register hotkey: Unknown scancode for F24"]
    when :windows then [unusual("Fn"), "Unable to register hotkey: Unknown VKCode for Fn"]
    else [unusual("Fn"), "Unable to register hotkey: Unknown scancode for key: Fn"]
    end
  end

  private def skip_unless_platform(platform)
    skip "#{platform} only; ferro-global-hotkey was built for #{PLATFORM}" unless PLATFORM == platform
  end

  # The shared plugin, after the Linux tests have pointed this process at
  # the private X server (or skipped).
  private def shared
    require_x_server if PLATFORM == :linux
    GlobalShortcutTest.shared
  end

  # A webview on +handle+ whose native webview records what it evaluates.
  private def recording_webview(handle)
    window = Tokra::Window.new(label: "main", native: Object.new, app_handle: handle)
    Tokra::Webview.new(label: "main", native: StubNative::WebView.new, window:, app_handle: handle)
  end

  # An invoke of +command+ from +webview+ whose answers land in the
  # returned Queue as <tt>[success, value]</tt>.
  private def build_invoke(webview, command, payload = {})
    answers = Thread::Queue.new
    invoke = Tokra::Ipc::Invoke.new(
      command:,
      payload:,
      webview:,
      responder: -> (success, json) { answers << [success, JSON.parse(json)] }
    )
    [invoke, answers]
  end

  # Runs +command+ with +payload+ through the shared plugin from +webview+
  # and returns its answer.
  private def answer(command, payload = {}, webview: recording_webview(shared.handle))
    invoke, answers = build_invoke(webview, command, payload)
    assert shared.plugin.extend_api(invoke), "the plugin should claim #{command}"
    answers.pop(timeout: 5)
  end

  # The rejection message for +command+ with +payload+.
  private def rejection(command, payload)
    success, value = answer(command, payload)
    refute success, "#{command} #{payload.inspect} should reject, but resolved #{value.inspect}"
    value
  end

  # Runs +script+ in a fresh Ruby with the plugin and StubNative loaded,
  # with +env+ added to its environment, and returns the value its last
  # expression marshals to standard output, and its standard error. A
  # child that outlives CHILD_LIMIT is killed and the test fails.
  private def in_child(script, env = {})
    child = <<~RUBY
      require "tokra-global-shortcut"
      $LOAD_PATH.unshift #{File.expand_path('../../../../test', __dir__).dump}
      require "support/stub_native"
      G = Tokra::Plugins::GlobalShortcut
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

  # Runs +script+ in a child pointed at the private X server on Linux.
  private def in_display_child(script)
    require_x_server if PLATFORM == :linux
    in_child(script, (PLATFORM == :linux) ? XServer.env : {})
  end

  #--
  # SPDX-SnippetBegin
  # SPDX-License-Identifier: Apache-2.0 OR MIT
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-SnippetComment: the private X server, adapted from
  #   ferro-global-hotkey's test/test_helper.rb (Ferro ef2407b)
  #++

  # A private X server for the Linux tests: Xvfb on a display of its own,
  # with F17 to F19 and F24 mapped to spare keycodes, since Xvfb's default
  # keymap stops at F12. It needs Xvfb, xdotool, and xmodmap; without them
  # the tests that need it skip.
  module XServer
    # The programs the server needs.
    PROGRAMS = %w[Xvfb xdotool xmodmap].freeze

    # The keys the tests register, which the server's keymap gains.
    KEYS = %w[F17 F18 F19 F24].freeze

    class << self
      # Starts Xvfb, once, and returns why it cannot, or nil.
      def start
        return @missing if defined?(@missing)

        @missing = missing_reason
        launch unless @missing
        @missing
      end

      # The private server's display, such as <tt>:3</tt>.
      attr_reader :display

      # The environment that points a program at the private server.
      def env
        { "DISPLAY" => display, "WAYLAND_DISPLAY" => nil, "GDK_BACKEND" => "x11" }
      end

      # Runs +arguments+ against the private server and returns its
      # standard output.
      def run(*arguments)
        output, status = Open3.capture2e(env, *arguments)
        raise "#{arguments.join(' ')} failed: #{output}" unless status.success?

        output
      end

      # Presses +keys+, xdotool's spelling, on the private server.
      def press(keys)
        run("xdotool", "key", "--delay", "100", keys)
      end

      private def missing_reason
        return "needs Linux" unless GlobalShortcutTest::PLATFORM == :linux

        absent = PROGRAMS.reject { |program| which(program) }
        absent.empty? ? nil : "needs #{absent.join(', ')}"
      end

      private def which(program)
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, program)) }
      end

      private def launch
        reader, writer = IO.pipe
        # -noreset keeps the keymap when the last client disconnects, which
        # would otherwise reset the server.
        @pid = spawn("Xvfb", "-displayfd", writer.fileno.to_s, "-nolisten", "tcp", "-noreset",
          "-screen", "0", "800x600x24", writer => writer, :out => File::NULL, :err => File::NULL)
        writer.close
        number = reader.gets or raise "Xvfb did not report its display"
        reader.close
        @display = ":#{number.strip}"
        map_keys
        Minitest.after_run { stop }
      end

      # Gives each of KEYS one of the keycodes the keymap leaves empty.
      private def map_keys
        spare = run("xmodmap", "-pke").lines.filter_map { |line| line[/\Akeycode\s+(\d+) =\s*\z/, 1] }
          .map { |code| Integer(code) }.select { |code| code >= 9 }
        raise "the private X server has too few spare keycodes" if spare.size < KEYS.size

        KEYS.zip(spare).each { |key, code| run("xmodmap", "-e", "keycode #{code} = #{key}") }
      end

      private def stop
        Process.kill(:TERM, @pid)
        Process.wait(@pid)
      rescue Errno::ESRCH, Errno::ECHILD
        nil
      end
    end
  end

  # Skips unless the private X server runs, and points this process at it,
  # so a manager made here grabs keys on that server.
  private def require_x_server
    missing = XServer.start
    skip "the private X server #{missing}" if missing
    ENV["DISPLAY"] = XServer.display
    ENV.delete("WAYLAND_DISPLAY")
  end

  #--
  # SPDX-SnippetEnd
  #++
end
