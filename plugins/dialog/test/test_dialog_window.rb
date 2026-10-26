# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/dialog_test"
require "integration/support/real_app"

# The dialog plugin in a real window, called from the page through Tauri's
# own api-iife.js (plugins-workspace d4613ff0), the client
# @tauri-apps/plugin-dialog builds.
#
# On macOS the file dialogs are real sheets on the window, which the
# fixture ends through AppKit as a click would. Message dialogs there are
# system alerts only a person can dismiss, so the page leaves them out. On
# Linux every dialog runs a fake zenity that answers as the page arranged,
# with D-Bus pointed nowhere so rfd skips the portal.
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

  # On Linux, a folder whose bin/zenity is the fake, first on PATH.
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
      "DBUS_SESSION_BUS_ADDRESS" => "unix:path=#{File.join(dir, 'no-bus')}",
    }
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
    assert_equal [
      "--no-markup",
      "--warning",
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
