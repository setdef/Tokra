# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/real_app"

# Events between Ruby and a real page through the vendored
# @tauri-apps/api client, and window events the page hears as tauri://
# events after Ruby resizes and moves its window (plan 047). No input is
# synthesized; Ruby's own setters make the platform report the change.
class EventTest < RealApp::TestCase
  def setup
    super
    @run = self.class.fixture_run { RealApp.launch("event") }
    assert_finished @run
  end

  def test_exits_cleanly_once_every_check_passed
    assert_equal 0, @run.status, @run.describe
  end

  def test_the_page_hears_rubys_events_with_tauris_shape
    detail = check_detail(@run, "listen hears what Ruby emits")

    assert_equal "ruby-says", detail["event"]
    assert_equal({ "n" => 1, "f" => 1.5 }, detail["payload"])
    assert_equal "number", detail["id"]
  end

  def test_once_and_unlisten
    assert_equal ["x"], check_detail(@run, "once hears one event")["seen"]
    assert_empty check_detail(@run, "unlisten stops delivery")["seen"]
  end

  # Ruby's handlers echo what they heard; the App-targeted emit reaches
  # neither the app's "to-window" listener (none) nor the window's, so the
  # window's only echo is 7, after the page's own emit.
  def test_ruby_hears_the_page_by_target
    echoes = check_detail(@run, "Ruby hears what the page emits, by target")["echoes"]

    assert_equal [{ "payload" => '{"x":[1]}', "as" => "app" }, { "payload" => "7", "as" => "window" }], echoes
  end

  def test_a_resize_is_heard_with_the_windows_inner_size
    detail = check_detail(@run, "a resize reaches the page as tauri://resize")

    assert_equal "tauri://resize", detail["event"]
    assert_equal({ "width" => 640, "height" => 480 }, detail["payload"])
    assert_equal detail["payload"], detail["inner"]
  end

  def test_a_move_is_heard_with_the_windows_position
    skip "Wayland gives no window position" if wayland?
    detail = check_detail(@run, "a move reaches the page as tauri://move")

    assert_equal "tauri://move", detail["event"]
    assert_equal({ "x" => 80, "y" => 120 }, detail["payload"])
    assert_equal detail["payload"], detail["outer"]
  end

  private def wayland?
    RbConfig::CONFIG["host_os"].include?("linux") && ENV["WAYLAND_DISPLAY"].to_s != "" &&
      ENV["GDK_BACKEND"] != "x11"
  end
end
