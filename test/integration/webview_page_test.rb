# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/real_app"

# A real webview's page and cookies (plan 052, 052e-2): navigate loads an
# HTTP page the fixture serves on localhost, url reads it back, reload
# loads it again, and the cookie methods read the cookie that page's
# server set, set one the reload's request carries, and delete it
# (webview/mod.rs:1662-1678, 2094-2164; tauri-runtime-wry lib.rs:3647-3656,
# 3758-3792). Every call runs inside the page-load hook, which the event
# loop calls, so the platform's wait for its cookie store runs inside the
# loop's callback (decision e2-1), and one runs from another thread, which
# waits for the main thread. Each line is caused by the page or the
# request it reports; the timeout is a backstop. Its pages build no URL by
# hand, so it runs on Windows too.
class WebviewPageTest < RealApp::TestCase
  def self.page?
    false
  end

  WINDOWS = RUBY_PLATFORM.match?(/mswin|mingw|cygwin/)

  def setup
    super
    @run = self.class.fixture_run { RealApp.launch("webview_page") }
    assert_finished @run
    @port = @run.lines.grep(/\ASERVER /).first&.split&.last
  end

  def test_exits_cleanly_once_the_cookies_are_read_from_another_thread
    assert_equal 0, @run.status, @run.describe
    assert_includes @run.lines, "COOKIES thread page", @run.describe
    assert_equal ["EVENT exit-requested 0", "EVENT exit"], @run.lines.grep(/\AEVENT /), @run.describe
  end

  def test_navigate_loads_the_page_and_url_reads_it_back
    assert_includes @run.lines, "URL nav http://localhost:#{@port}/first", @run.describe
  end

  def test_reload_asks_the_server_again
    assert_equal ["REQUEST /first cookie=-", "REQUEST /first cookie=app,page"],
      @run.lines.grep(%r{\AREQUEST /first }), @run.describe
    assert_includes @run.lines, "RELOADED", @run.describe
  end

  # On Windows the fixture reads until each write shows, at most 50 times,
  # since WebView2 may answer a read before it applies a write; elsewhere
  # the first read must show it. Either way the answer must be the
  # settled one.
  def test_the_cookies_the_server_and_ruby_set_are_read_and_deleted
    assert_includes @run.lines, "COOKIES for-url page", @run.describe
    assert_includes @run.lines, "COOKIES all app,page", @run.describe
    assert_includes @run.lines, "COOKIES after-delete page", @run.describe
    reads = WINDOWS ? (1..50).map(&:to_s) : ["1"]
    %w[all after-delete].each do |label|
      line = @run.lines.find { |l| l.start_with?("READS #{label} ") }
      assert_includes reads, line&.split&.last, @run.describe
    end
    assert_includes @run.lines, "COOKIES thread page", @run.describe
  end
end
