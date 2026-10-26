# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/global_shortcut_test"
require "integration/support/real_app"

# The global-shortcut plugin in a real window, called from the page through
# Tauri's own api-iife.js (plugins-workspace d4613ff0), the client
# @tauri-apps/plugin-global-shortcut builds, with its Channel.
#
# On Linux the app runs on the suite's private Xvfb, and once the page has
# registered its shortcut the test presses it there with xdotool, so the
# press travels from global-hotkey's X11 thread through the plugin's
# handler and the page's Channel to the page. Elsewhere the page registers
# and unregisters a combination nobody uses, and nothing is pressed.
class TestGlobalShortcutWindow < RealApp::TestCase
  include GlobalShortcutTest

  FIXTURES = File.expand_path("integration/fixtures", __dir__)

  def setup
    require_x_server if PLATFORM == :linux
    super
    @run = self.class.fixture_run { launch }
    assert_finished @run
  end

  private def launch
    return RealApp.launch("global-shortcut", fixtures: FIXTURES) unless PLATFORM == :linux

    press = lambda do |line, _pid|
      XServer.press("ctrl+alt+shift+F24") if line.chomp == "REGISTERED"
      false
    end
    RealApp.launch("global-shortcut", fixtures: FIXTURES, env: XServer.env.merge("FIXTURE_PRESSES" => "1"), on_line: press)
  end

  def test_exits_cleanly_once_every_check_passed
    assert_equal 0, @run.status, @run.describe
  end

  def test_the_page_registers_and_unregisters
    assert_equal({ "registered" => false }, check_detail(@run, "nothing is registered at first"))
    assert_equal({ "result" => nil, "registered" => true }, check_detail(@run, "register registers"))
    check_detail(@run, "unregister unregisters")
    check_detail(@run, "unregisterAll unregisters every shortcut")
  end

  def test_the_page_sees_tauris_errors
    assert_match(/\ACouldn't recognize "bogus" as a valid key for hotkey/,
      check_detail(@run, "a shortcut that does not parse rejects with its message")["rejected"])
    assert_equal "invalid args `shortcut` for command `is_registered`: invalid type: integer `1`, expected a string",
      check_detail(@run, "a bad argument rejects with Tauri's message")["rejected"]
  end

  # ShortcutJsEvent through the page's Channel (lib.rs:268-302).
  def test_each_press_reaches_the_page
    skip "only Linux presses keys, on the suite's own Xvfb" unless PLATFORM == :linux

    id = G::Shortcut.from_str("ctrl+alt+shift+F24").id
    assert_equal [
      { "shortcut" => "shift+control+alt+F24", "id" => id, "state" => "Pressed" },
      { "shortcut" => "shift+control+alt+F24", "id" => id, "state" => "Released" },
    ], check_detail(@run, "each press reaches the handler through its channel")["events"]
  end
end
