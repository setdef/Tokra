# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/real_app"

# Two real windows and webviews, each event routed by its label (plan 052,
# phase 1). tao names a window event's window by an id the native layer
# turns into the window's label, and wry hands a protocol handler the id
# the webview was built with, its label, as Tauri's runtime resolves them
# (tauri-runtime-wry lib.rs:4126-4150, 4625; manager/webview.rs:229-233).
# Were either lost, closing "second" would close "main", the app would
# exit after "second", or no PROTOCOL line would name "side".
#
# "main"'s own lines interleave with "side"'s, so each label's lines are
# checked in order on their own. Each step the fixture takes is caused by
# the line before it, so these orders hold on every run. Its page builds no
# URL by hand, so it runs on Windows as well (RealApp.unavailable_reason).
class MultiwindowRoutingTest < RealApp::TestCase
  def self.page?
    false
  end

  def setup
    super
    @run = self.class.fixture_run { RealApp.launch("multiwindow_routing") }
    assert_finished @run
  end

  def test_exits_cleanly_after_the_last_window
    assert_equal 0, @run.status, @run.describe
  end

  def test_the_side_webviews_request_and_load_name_it
    assert_in_order "PROTOCOL side", "PAGE side finished"
  end

  # The ipc:// handler reads wry's id, and the postMessage handler the
  # label it captured (tauri-runtime-wry lib.rs:5169-5192;
  # ipc/protocol.rs:32-36, 59-61).
  def test_each_invoke_names_the_webview_that_sent_it
    assert_includes @run.lines, "INVOKE side ipc-protocol", @run.describe
    assert_includes @run.lines, "INVOKE side post-message", @run.describe
    assert_empty @run.lines.grep(/\AINVOKE (?!side )/), @run.describe
  end

  def test_the_second_window_closes_alone_once_both_pages_loaded_and_both_invokes_arrived
    ["PAGE main finished", "PAGE side finished", "INVOKE side ipc-protocol", "INVOKE side post-message"].each do |line|
      assert_in_order line, "EVENT second Tokra::WindowEvent::CloseRequested",
        "EVENT second Tokra::WindowEvent::Destroyed"
    end
  end

  def test_the_main_window_closes_after_the_second_and_then_the_app_exits
    assert_in_order "EVENT second Tokra::WindowEvent::Destroyed", "EVENT main Tokra::WindowEvent::CloseRequested",
      "EVENT main Tokra::WindowEvent::Destroyed", "EVENT exit-requested nil", "EVENT exit"
  end

  def test_no_exit_is_asked_before_the_last_window_goes
    asked = @run.lines.index("EVENT exit-requested nil")
    destroyed = @run.lines.index("EVENT main Tokra::WindowEvent::Destroyed")
    refute_nil asked, @run.describe
    refute_nil destroyed, @run.describe
    assert_operator asked, :>, destroyed, @run.describe
    assert_equal 1, @run.lines.count("EVENT exit-requested nil"), @run.describe
  end

  def test_the_main_webview_names_itself_too
    assert_in_order "PROTOCOL main", "PAGE main finished"
  end

  # Each of +lines+ appears, each after the one before it.
  private def assert_in_order(*lines)
    indexes = lines.map { |line| @run.lines.index(line) }
    assert indexes.none?(&:nil?), "missing #{lines.zip(indexes).select { |_, i| i.nil? }.map(&:first)}\n#{@run.describe}"
    assert_equal indexes.sort, indexes, "out of order: #{lines.inspect}\n#{@run.describe}"
  end
end
