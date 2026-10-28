# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/real_app"

# The vendored @tauri-apps/api TrayIcon class against the tray plugin, with
# the tray read back from the platform (plan 043). No menu opens.
class TrayPluginTest < RealApp::TestCase
  def setup
    super
    @run = self.class.fixture_run { RealApp.launch("tray_plugin") }
    assert_finished @run
  end

  def test_exits_cleanly_once_every_check_passed
    assert_equal 0, @run.status, @run.describe
  end

  def test_the_pages_tray_reaches_the_platform_and_hears_its_events
    detail = check_detail(@run, "a tray the page builds, changes, and closes")

    assert_equal "js-tray", detail["id"]
    case detail["os"]
    when "macos"
      assert_equal [{ "image" => true, "tooltip" => "JS Tip", "title" => "JS Title", "menu" => ["Open"] }], detail["built"]
      assert_equal [{ "image" => false, "tooltip" => "JS Changed", "title" => "JS Changed Title", "menu" => ["Open"] }], detail["changed"]
      assert_empty detail["hidden"]
      assert_equal [%w[Enter js-tray], %w[Move js-tray], %w[Leave js-tray]], detail["shapes"].map { |shape| shape.first(2) }
    when "windows"
      assert_equal 1, detail["built"]
      assert_equal [["Enter", nil, nil], %w[Click Left Down], %w[Click Left Up], ["DoubleClick", "Left", nil]],
        detail["shapes"].map { |shape| [shape[0], shape[5], shape[6]] }
    else
      assert_equal 1, detail["built"].size
      assert_empty detail["shapes"], "Linux's tray-icon sends no events"
    end
    assert(detail["shapes"].all? { |shape| shape[2..4] == [true, true, true] }, "the page maps each position and size")
    assert_includes [[], 0], detail["closed"]
    assert_equal "Can't find a tray associated with this id: js-tray", detail["removeError"]
  end
end
