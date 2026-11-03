# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/real_app"

# Real webviews built with WebviewWindowBuilder's webview rows (plan 052,
# 052e-1), each a wry webview whose page reports what its row did:
# user_agent becomes navigator.userAgent, a main-frame script runs in the
# page and not its iframe while an all-frames script runs in both, and
# disable_javascript shows the page's noscript (webview/mod.rs:873-948,
# 1163-1166; tauri-runtime-wry lib.rs:4661-4663, 4857-4859, 4958-4961).
# Each line is caused by the page it reports; timeouts are backstops. Its
# pages build no URL by hand, so it runs on Windows too.
class WebviewRowsTest < RealApp::TestCase
  def self.page?
    false
  end

  WINDOWS = RUBY_PLATFORM.match?(/mswin|mingw|cygwin/)

  def setup
    super
    @run = self.class.fixture_run { RealApp.launch("webview_rows") }
    assert_finished @run
  end

  def test_exits_cleanly_once_every_page_has_reported
    assert_equal 0, @run.status, @run.describe
    assert_equal ["EVENT exit-requested 0", "EVENT exit"], @run.lines.grep(/\AEVENT /), @run.describe
  end

  def test_a_user_agent_is_the_pages_navigator_user_agent
    assert_includes @run.lines, "AGENT agent TokraProbe/1.0 (webview rows)", @run.describe
  end

  # wry adds every script to subframes on Windows, whatever its frame
  # (wry lib.rs:982-984), so there the iframe sees the main-frame script
  # too.
  def test_a_main_frame_script_stays_out_of_iframes_and_an_all_frames_script_runs_in_them
    assert_includes @run.lines, "SCRIPTS frames main=true all=true", @run.describe
    assert_includes @run.lines, "FRAME frames main=#{WINDOWS} all=true", @run.describe
  end

  def test_a_page_without_javascript_shows_its_noscript
    assert_includes @run.lines, "IMAGE nojs nojs.png", @run.describe
    refute_includes @run.lines, "IMAGE nojs js.png", @run.describe
  end
end
