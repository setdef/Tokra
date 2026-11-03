# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/real_app"

# Real windows made at run time through WebviewWindowBuilder (plan 052,
# phase 2): "main" before the setup hook, "cmd" from a command on the main
# thread, and "thread" from a Ruby thread, each a real tao window and wry
# webview whose page loads. Tauri's order holds end to end: plugins hear
# the window before the webview, and the page, through @tauri-apps/api's
# listen, hears tauri://webview-created before tauri://window-created
# (manager/window.rs:112-121; manager/webview.rs:603-634;
# window/mod.rs:410-424).
#
# On Windows "cmd" is the first WebView2 built inside the running loop,
# whose creation pumps a nested message loop there, as Tauri's does for its
# config windows (plan 052, decision 5). Each line the test orders is
# caused by the one before it; timeouts are backstops. Its page builds no
# URL by hand, so it runs on Windows too (RealApp.unavailable_reason).
class WebviewWindowBuilderTest < RealApp::TestCase
  def self.page?
    false
  end

  def setup
    super
    @run = self.class.fixture_run { RealApp.launch("webview_window_builder") }
    assert_finished @run
  end

  def test_exits_cleanly_once_every_window_has_loaded
    assert_equal 0, @run.status, @run.describe
    assert_in_order "PAGE cmd finished", "EVENT exit-requested 0", "EVENT exit"
    assert_in_order "PAGE thread finished", "EVENT exit-requested 0"
  end

  def test_main_is_built_and_announced_before_the_setup_hook
    assert_in_order "PLUGIN window_created main", "PLUGIN webview_created main", "SETUP main=true"
  end

  def test_a_window_built_on_the_main_thread_exists_when_build_returns
    assert_in_order "PLUGIN window_created cmd", "PLUGIN webview_created cmd", "BUILT cmd built (cmd)"
  end

  # tao builds the window at the size the builder asked for
  # (WindowBuilder::with_inner_size).
  def test_a_window_has_the_inner_size_its_builder_asked_for
    assert_includes @run.lines, "SIZE cmd 240x180", @run.describe
  end

  # Its title query waits behind the queued creation; ahead of it the
  # window would be empty and the query would raise.
  def test_a_window_built_on_another_thread_answers_a_query_made_at_once
    assert_includes @run.lines, "TITLE thread built (thread)", @run.describe
    assert_in_order "PLUGIN window_created thread", "PLUGIN webview_created thread"
  end

  # Each webview opens the page its WebviewUrl::App names, "main" the app
  # URL itself (manager/webview.rs:414-430).
  def test_each_webview_asks_for_the_page_its_url_names
    ["REQUEST main /", "REQUEST cmd /cmd.html", "REQUEST thread /thread.html"].each do |line|
      assert_includes @run.lines, line, @run.describe
    end
  end

  def test_the_page_hears_webview_created_before_window_created
    %w[cmd thread].each do |label|
      assert_includes @run.lines, "HEARD #{label} tauri://webview-created tauri://window-created", @run.describe
    end
  end

  # Each of +lines+ appears, each after the one before it.
  private def assert_in_order(*lines)
    indexes = lines.map { |line| @run.lines.index(line) }
    assert indexes.none?(&:nil?), "missing #{lines.zip(indexes).select { |_, i| i.nil? }.map(&:first)}\n#{@run.describe}"
    assert_equal indexes.sort, indexes, "out of order: #{lines.inspect}\n#{@run.describe}"
  end
end
