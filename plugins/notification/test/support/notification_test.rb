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
require "tokra-notification"

# Tokra's StubNative double lives with the core tests; plugins exercise a
# real AppHandle built on it instead of a hand-rolled stand-in.
$LOAD_PATH.unshift File.expand_path("../../../../test", __dir__)
require "support/stub_native"

# Helpers every notification test shares: a real app handle, invokes that
# record their answer, a child Ruby for the macOS tests, and a real
# notification server for the Linux ones.
module NotificationTest
  Notification = Tokra::Plugins::Notification

  # The platform ferro-notify-rust's extension was built for, as
  # notify-rust's cfg decides.
  PLATFORM = Ferro::NotifyRust.const_get(:PLATFORM)

  # This plugin's lib directory, for child processes.
  LIB = File.expand_path("../../lib", __dir__)

  # How long a child may run before it is killed, in seconds.
  CHILD_LIMIT = 30

  # The title every notification a test sends carries, so the macOS
  # sweeper removes only these.
  TITLE = "tokra-notification test"

  # On macOS, naming the app changes this process's bundle identifier for
  # good, and a send may show the maintainer a notification, so the test
  # process refuses both; the macOS tests do them in a child, which does
  # not load this file.
  module RefuseMacosSends
    # Raises: the test process never names the app.
    def name_application
      raise "a macOS test named the app in the test process; use in_child"
    end

    # Raises: the test process never sends.
    def show
      raise "a macOS test sent a notification from the test process; use in_child"
    end
  end
  Notification::Imp::Notification.prepend(RefuseMacosSends) if PLATFORM == :macos

  private def skip_unless_platform(platform)
    skip "#{platform} only; ferro-notify-rust was built for #{PLATFORM}" unless PLATFORM == platform
  end

  # A real app handle, built exactly as an app builds one.
  private def build_app
    Tokra::Builder.default.build(native: StubNative)
  end

  # A real app handle whose configuration names +identifier+ and
  # +product_name+, which Tokra has no builder setting for yet.
  private def configured_handle(identifier: nil, product_name: nil)
    config = Tokra::Config.new(identifier:, product_name:, version: nil)
    Tokra::AppHandle.new(Tokra::AppManager.new(config:, webviews: {}, windows: {}))
  end

  # A registered plugin on a real handle.
  private def build_plugin(app = build_app)
    plugin = Notification::Plugin.new(app.handle)
    app.handle.plugin(plugin)
    plugin
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

  # The rejection message for +command+ with +payload+.
  private def rejection(command, payload)
    success, value = answer(command, payload)
    refute success, "#{command} #{payload.inspect} should reject, but resolved #{value.inspect}"
    value
  end

  # The rejection message for notify with +options+.
  private def notify_rejection(options)
    rejection("notify", { "options" => options })
  end

  # Runs +script+ in a fresh Ruby with the plugin loaded, with +env+ added
  # to its environment, and returns the value its last expression
  # marshals to standard output, and its standard error. A child that
  # outlives CHILD_LIMIT is killed and the test fails.
  private def in_child(script, env = {})
    child = <<~RUBY
      require "tokra-notification"
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

  #--
  # SPDX-SnippetBegin
  # SPDX-License-Identifier: MIT OR Apache-2.0
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-SnippetComment: the private session bus and dunst, adapted from
  #   ferro-notify-rust's test/test_helper.rb (Ferro c4b1c5b)
  #++

  # A real notification server for the Linux tests: dunst, on a session bus
  # of the suite's own, so nothing reaches the user's desktop, with
  # dbus-monitor recording every Notify call that reaches it. It needs
  # dbus-daemon, dbus-monitor, dunst, and a display (X11 or Wayland) for
  # dunst to draw on; without them the tests that need it skip.
  module Server
    # The programs the server needs.
    PROGRAMS = %w[dbus-daemon dbus-monitor dunst dunstctl].freeze

    # One Notify call as the server received it.
    Call = Data.define(:app_name, :replaces_id, :app_icon, :summary, :body, :hints)

    class << self
      # The bus address, once the bus and dunst run.
      attr_reader :address

      # Starts the bus, dunst, and the monitor, once. Returns why it
      # cannot, or nil.
      def start
        return @missing if defined?(@missing)

        @missing = missing_reason
        launch unless @missing
        @missing
      end

      # Runs +arguments+ against the suite's bus and returns its standard
      # output.
      def run(*arguments)
        output, status = Open3.capture2e({ "DBUS_SESSION_BUS_ADDRESS" => @address }, *arguments)
        raise "#{arguments.join(' ')} failed: #{output}" unless status.success?

        output
      end

      # The Notify calls the monitor has seen, oldest first.
      def calls
        File.read(@log).split(/^method call /).drop(1).filter_map { |call| parse(call) }
      end

      # Waits up to five seconds for a Notify call whose summary is
      # +summary+, and returns it, or nil.
      def call_with_summary(summary)
        50.times do
          found = calls.find { |call| call.summary == summary }
          return found if found

          sleep 0.1
        end
        nil
      end

      private def missing_reason
        return "needs Linux" unless NotificationTest::PLATFORM == :linux

        absent = PROGRAMS.reject { |program| which(program) }
        return "needs #{absent.join(', ')}" unless absent.empty?
        return "needs a display (DISPLAY or WAYLAND_DISPLAY) for dunst" unless ENV["DISPLAY"] || ENV["WAYLAND_DISPLAY"]

        nil
      end

      private def which(program)
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, program)) }
      end

      private def launch
        @dir = Dir.mktmpdir("tokra-notification-test")
        output, status = Open3.capture2("dbus-daemon", "--session", "--fork", "--print-address=1", "--print-pid=1",
          "--address=unix:path=#{@dir}/bus")
        raise "dbus-daemon failed: #{output}" unless status.success?

        @address, pid = output.lines.map(&:strip)
        @bus = Integer(pid)
        env = { "DBUS_SESSION_BUS_ADDRESS" => @address }
        @log = File.join(@dir, "monitor.log")
        @monitor = spawn(env, "dbus-monitor", "--session",
          "type='method_call',interface='org.freedesktop.Notifications',member='Notify'", out: @log, err: File::NULL)
        config = File.join(@dir, "dunstrc")
        File.write(config, "[global]\n    idle_threshold = 0\n    history_length = 50\n")
        @dunst = spawn(env, "dunst", "-config", config, out: File::NULL, err: File.join(@dir, "dunst.log"))
        wait_for_dunst
        Minitest.after_run { stop }
      end

      private def wait_for_dunst
        50.times do
          output, status = Open3.capture2e({ "DBUS_SESSION_BUS_ADDRESS" => @address }, "dunstctl", "is-paused")
          return if status.success? && output.strip == "false" && File.size?(@log)

          sleep 0.1
        end
        raise "dunst did not start: #{File.read(File.join(@dir, 'dunst.log'))}"
      end

      # A Notify call from dbus-monitor's text: app name, replaces id,
      # icon, summary, body, the actions, the hints, and the timeout.
      private def parse(text)
        return nil unless text.include?("member=Notify")

        strings = text.lines.drop(1).take_while { |line| !line.include?("array [") }
          .map { |line| line.chomp[/\A\s*(?:string|uint32) (.*)\z/, 1] }.compact
        hints = text.scan(/dict entry\(\s*string "([^"]*)"\s*variant\s+\w+ (.*?)\s*\)/m).to_h do |key, value|
          [key, value.delete_prefix('"').delete_suffix('"')]
        end
        app_name, replaces_id, app_icon, summary, body = strings.map { |value| value.delete_prefix('"').delete_suffix('"') }
        Call.new(app_name:, replaces_id:, app_icon:, summary:, body:, hints:)
      end

      private def stop
        [@monitor, @dunst, @bus].compact.each do |pid|
          Process.kill(:TERM, pid)
        rescue Errno::ESRCH
          nil
        end
        [@monitor, @dunst].compact.each { |pid| Process.wait(pid) }
        FileUtils.remove_entry(@dir) if @dir
      end
    end
  end

  #--
  # SPDX-SnippetEnd
  #++

  # Skips unless the Linux notification server runs, and points this
  # process's D-Bus at it.
  private def require_server
    missing = Server.start
    skip "the notification server #{missing}" if missing
    ENV["DBUS_SESSION_BUS_ADDRESS"] = Server.address
  end

  # Removes this suite's delivered notifications, found by TITLE, every
  # half second, so a Mac that does show one hides it at once. Uses
  # AppKit through Fiddle from a Ruby thread. The script a macOS child
  # runs before it sends anything, from ferro-notify-rust's macOS tests.
  SWEEPER = <<~RUBY
    require "fiddle"
    objc = Fiddle.dlopen("/usr/lib/libobjc.A.dylib")
    Fiddle.dlopen("/System/Library/Frameworks/Foundation.framework/Foundation")
    pointer = Fiddle::TYPE_VOIDP
    message = objc["objc_msgSend"]
    send = Fiddle::Function.new(message, [pointer, pointer], pointer)
    count = Fiddle::Function.new(message, [pointer, pointer], Fiddle::TYPE_LONG)
    at = Fiddle::Function.new(message, [pointer, pointer, Fiddle::TYPE_LONG], pointer)
    remove = Fiddle::Function.new(message, [pointer, pointer, pointer], Fiddle::TYPE_VOID)
    get_class = Fiddle::Function.new(objc["objc_getClass"], [pointer], pointer)
    selector = Fiddle::Function.new(objc["sel_registerName"], [pointer], pointer)
    push = Fiddle::Function.new(objc["objc_autoreleasePoolPush"], [], pointer)
    pop = Fiddle::Function.new(objc["objc_autoreleasePoolPop"], [pointer], Fiddle::TYPE_VOID)
    sweep = lambda do
      pool = push.call
      center = send.call(get_class.call("NSUserNotificationCenter"), selector.call("defaultUserNotificationCenter"))
      delivered = send.call(center, selector.call("deliveredNotifications"))
      count.call(delivered, selector.call("count")).times.map { |index| at.call(delivered, selector.call("objectAtIndex:"), index) }
        .select do |each|
          title = send.call(each, selector.call("title"))
          !title.null? && send.call(title, selector.call("UTF8String")).to_s == #{TITLE.dump}
        end
        .each { |each| remove.call(center, selector.call("removeDeliveredNotification:"), each) }
    ensure
      pop.call(pool)
    end
    Thread.new do
      loop do
        sleep 0.5
        sweep.call
      end
    end
  RUBY

  # Ruby for a macOS child: reads what this process reports as its main
  # bundle's identifier, which notify-rust's set_application replaces.
  BUNDLE_IDENTIFIER = <<~RUBY
    require "fiddle"
    def bundle_identifier
      objc = Fiddle.dlopen("/usr/lib/libobjc.A.dylib")
      Fiddle.dlopen("/System/Library/Frameworks/Foundation.framework/Foundation")
      pointer = Fiddle::TYPE_VOIDP
      send = Fiddle::Function.new(objc["objc_msgSend"], [pointer, pointer], pointer)
      get_class = Fiddle::Function.new(objc["objc_getClass"], [pointer], pointer)
      selector = Fiddle::Function.new(objc["sel_registerName"], [pointer], pointer)
      bundle = send.call(get_class.call("NSBundle"), selector.call("mainBundle"))
      identifier = send.call(bundle, selector.call("bundleIdentifier"))
      identifier.null? ? nil : send.call(identifier, selector.call("UTF8String")).to_s
    end
  RUBY
end
