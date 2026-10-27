# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/dialog_test"
require "integration/support/real_app"
require "open3"

# The dialog plugin in a real window, called from the page through Tauri's
# own api-iife.js (plugins-workspace d4613ff0), the client
# @tauri-apps/plugin-dialog builds.
#
# On macOS the file dialogs are real sheets on the window, which the
# fixture ends through AppKit as a click would. Message dialogs there are
# system alerts only a person can dismiss, so the page leaves them out. On
# Linux every dialog runs a fake zenity that answers as the page arranged.
# rfd asks the desktop portal first, over D-Bus, naming the parent window
# (rfd 0.17.2 src/backend/xdg_desktop_portal.rs:82-113); the app's bus is
# one of the test's own, where no portal answers, and dbus-monitor records
# what rfd asked, so the test sees the window the commands passed as
# parent (ADR 013).
class TestDialogWindow < RealApp::TestCase
  FIXTURES = File.expand_path("integration/fixtures", __dir__)

  FAKE_ZENITY = <<~SH
    #!/bin/sh
    printf '%s\\n' "$@" > "$FAKE_ZENITY_DIR/log"
    sleep "$(cat "$FAKE_ZENITY_DIR/delay" 2>/dev/null || echo 0)"
    cat "$FAKE_ZENITY_DIR/output" 2>/dev/null
    exit "$(cat "$FAKE_ZENITY_DIR/status" 2>/dev/null || echo 0)"
  SH

  def setup
    super
    @run = self.class.fixture_run { RealApp.launch("dialog", fixtures: FIXTURES, env: self.class.environment) }
    assert_finished @run
  end

  # A session bus with no services, so a portal call fails at once and
  # rfd falls back to zenity, and one that lets dbus-monitor watch.
  BUS_CONFIG = <<~XML
    <!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
      "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
    <busconfig>
      <type>session</type>
      <listen>unix:path=%<path>s</listen>
      <auth>EXTERNAL</auth>
      <policy context="default">
        <allow send_destination="*" eavesdrop="true"/>
        <allow eavesdrop="true"/>
        <allow own="*"/>
      </policy>
    </busconfig>
  XML

  # On Linux, a folder whose bin/zenity is the fake, first on PATH, and a
  # bus of the test's own with dbus-monitor recording the portal calls, or,
  # without dbus-daemon and dbus-monitor, a bus that does not exist.
  def self.environment
    return {} unless RUBY_PLATFORM.include?("linux")

    dir = Dir.mktmpdir("tokra-dialog-zenity")
    bin = File.join(dir, "bin")
    Dir.mkdir(bin)
    File.write(File.join(bin, "zenity"), FAKE_ZENITY)
    File.chmod(0o755, File.join(bin, "zenity"))
    {
      "PATH" => "#{bin}:#{ENV.fetch('PATH')}",
      "FAKE_ZENITY_DIR" => dir,
      "DBUS_SESSION_BUS_ADDRESS" => start_bus(dir) || "unix:path=#{File.join(dir, 'no-bus')}",
    }
  end

  # Starts dbus-daemon and dbus-monitor in +dir+ and returns the bus's
  # address, or +nil+ without them. The monitor writes to +dir+/portal.log.
  def self.start_bus(dir)
    return nil unless %w[dbus-daemon dbus-monitor].all? { |program| system("command -v #{program} >/dev/null 2>&1") }

    config = File.join(dir, "bus.conf")
    File.write(config, format(BUS_CONFIG, path: File.join(dir, "bus")))
    output, status = Open3.capture2("dbus-daemon", "--config-file=#{config}", "--fork", "--print-address=1",
      "--print-pid=1")
    return nil unless status.success?

    address, pid = output.lines.map(&:strip)
    @portal_log = File.join(dir, "portal.log")
    monitor = Process.spawn("dbus-monitor", "--address", address, "interface='org.freedesktop.portal.FileChooser'",
      out: @portal_log, err: File::NULL)
    50.times { File.size?(@portal_log) ? break : sleep(0.1) }
    Minitest.after_run do
      [monitor, Integer(pid)].each { |id| RealApp.signal(id, :TERM) }
      Process.wait(monitor)
    end
    address
  end

  class << self
    # Where dbus-monitor recorded the portal calls, or +nil+.
    attr_reader :portal_log
  end

  # The parent_window string rfd sent with each FileChooser call, by
  # method, in order: dbus-monitor prints the method, then its first
  # argument, the parent (xdg-desktop-portal's FileChooser API).
  def portal_parents
    log = self.class.portal_log
    skip "no dbus-daemon and dbus-monitor to watch the portal calls" unless log

    File.read(log).scan(/member=(\w+)\n\s*string "([^"]*)"/)
  end

  def test_exits_cleanly_once_every_check_passed
    assert_equal 0, @run.status, @run.describe
  end

  # defaultPath names a file that does not exist yet, so the dialog starts
  # in its folder with its name (commands.rs:100-120), and OK returns it.
  def test_save_resolves_the_chosen_path
    detail = check_detail(@run, "save resolves the chosen path")
    assert detail["path"].end_with?("/out.txt"), detail.inspect
    return unless RUBY_PLATFORM.include?("linux")

    assert_equal [
      "--no-markup",
      "--file-selection",
      "--save",
      "--confirm-overwrite",
      "--file-filter",
      "Text | *.txt",
      "--filename",
      "out.txt",
], detail["zenity"]
  end

  # Tauri parents save and message dialogs to the calling window on every
  # desktop, and open dialogs only on Windows and macOS
  # (commands.rs:129-132, 229-232, 281-284). On X11 rfd names the parent to
  # the portal as <tt>x11:</tt> and the window ID in hex
  # (window_identifier/mod.rs:70-83).
  def test_on_x11_save_names_the_window_to_the_portal_and_open_does_not
    skip "Linux only" unless RUBY_PLATFORM.include?("linux")
    line = @run.lines.find { |l| l.start_with?("WINDOW_HANDLE ") }
    refute_nil line, @run.describe
    handle = JSON.parse(line.delete_prefix("WINDOW_HANDLE "))
    skip "the window is not on X11: #{handle.inspect}" unless handle["kind"] == "XlibWindowHandle"

    parents = portal_parents
    assert_includes parents, ["SaveFile", "x11:#{handle['window'].to_s(16)}"], parents.inspect
    assert_includes parents, ["OpenFile", ""], parents.inspect
    refute parents.any? { |member, parent| member == "OpenFile" && !parent.empty? }, parents.inspect
  end

  def test_a_cancelled_open_resolves_null
    assert_nil check_detail(@run, "a cancelled open resolves null")["path"]
    check_detail(@run, "a cancelled multiple open resolves null or an empty list")
  end

  # The command waits on its own thread, and the dialog's future on
  # another, so the main thread keeps answering invokes while a dialog is
  # open (plan 023, decision 2).
  def test_the_event_loop_answers_while_a_dialog_is_open
    detail = check_detail(@run, "the event loop answers while a dialog is open")
    assert detail["dialogOpen"], "no dialog was open when the page pinged: #{detail.inspect}"
    assert detail["answeredWhileOpen"], detail.inspect
  end

  def test_a_bad_argument_rejects_with_tauris_message
    assert_equal "invalid args `options` for command `open`: invalid type: integer `1`, expected a string",
      check_detail(@run, "a bad argument rejects with Tauri's message")["rejected"]
  end

  def test_message_ask_and_confirm_on_linux
    skip "macOS message dialogs are system alerts only a person can dismiss" unless RUBY_PLATFORM.include?("linux")

    message = check_detail(@run, "message resolves the custom label pressed")
    # Two custom buttons make rfd ask zenity a --question, which takes no
    # level, so the warning kind does not reach it (rfd 0.17.2
    # src/backend/linux/zenity.rs:189-205).
    assert_equal [
      "--no-markup",
      "--question",
      "--title",
      "Draft",
      "--text",
      "Keep the draft?",
      "--ok-label",
      "Keep",
      "--cancel-label",
      "Drop",
], message["zenity"]
    check_detail(@run, "ask and confirm resolve booleans")
    overrides = check_detail(@run, "window.alert and window.confirm show the plugin's dialogs")
    assert_includes overrides["confirmArgs"], "Really?"
    assert_includes overrides["alertArgs"], "Hello"
  end
end
