# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "support/stub_native"
require_relative "support/test_app"

# The windows a config's app.windows lists, which App#run builds where
# Tauri's setup builds them: each one whose create is true, in order,
# before the setup hook (app.rs:2370-2384; plan 054, decision 14), each
# through WebviewWindowBuilder.from_config (decision 15).
class TestConfigWindows < Minitest::Test
  TWO_WINDOWS = {
    "app" => {
      "windows" => [
        { "label" => "first", "title" => "First", "width" => 640, "height" => 480 },
        { "label" => "second", "title" => "Second", "url" => "second.html", "width" => 320, "height" => 240 },
      ],
    },
  }.freeze

  def setup
    StubNative.clear_event
  end

  def teardown
    StubNative.clear_event
    Thread.current[:config_windows_found] = nil
  end

  def test_the_configured_windows_are_built_in_order_before_the_setup_hook
    hook = Ractor.shareable_proc do |app|
      Thread.current[:config_windows_found] = app.webview_windows.transform_values { |window| window.window.native.opened? }
    end
    run_test_app(Tokra::Builder.default.setup(&hook), config: TWO_WINDOWS)

    assert_equal({ "first" => true, "second" => true }, Thread.current[:config_windows_found])
    assert_equal ["First", "Second"], StubNative.windows.map(&:title)
    assert_equal [[640.0, 480.0], [320.0, 240.0]], StubNative.windows.map(&:size)
    assert_equal %w[first second], StubNative.webviews.map(&:label)
    app_url = Tokra::WebviewManager.tokra_protocol_url(Tokra::App.os_name).join("/").as_str
    assert_equal [app_url, "#{app_url}second.html"], StubNative.webviews.map(&:url)
  end

  def test_a_window_whose_create_is_false_is_skipped_and_still_in_the_config
    windows = [{ "label" => "later", "create" => false, "title" => "Later" }, { "label" => "now", "title" => "Now" }]
    config = { "app" => { "windows" => windows } }
    app = build_test_app(config:)
    app.run

    assert_equal ["Now"], StubNative.windows.map(&:title)
    assert_nil app.get_window("later")
    later = app.config.app.windows.first
    assert_equal ["later", false, "Later"], [later.label, later.create, later.title]
  end

  # As Tauri's app does with an empty app.windows (config.rs:2749-2750).
  def test_a_config_that_lists_no_window_opens_none
    app = build_test_app(config: { "app" => { "windows" => [] } })
    app.run

    assert_empty StubNative.windows
    assert_empty app.webview_windows
  end

  # Tauri's setup returns the builder's error, and its runtime panics with
  # "Failed to setup app: {e}" (app.rs:1297-1300); Tokra lets the error
  # itself end App#run, as a setup hook's does.
  def test_an_invalid_label_ends_run_with_the_builders_error
    hook = Ractor.shareable_proc { |_app| Thread.current[:config_windows_found] = :ran }
    app = build_test_app(Tokra::Builder.default.setup(&hook), config: { "app" => { "windows" => [{ "label" => "not ok" }] } })
    error = assert_raises(Tokra::Error::Runtime) { app.run }

    assert_equal "runtime error: #{Tokra::Error::Runtime::INVALID_WINDOW_LABEL}", error.message
    assert_nil Thread.current[:config_windows_found], "the setup hook ran after a config window failed"
  end

  # The 054a-3 shortcut took the label, URL, title, and size only; from
  # config takes every row its builder has.
  def test_a_configured_window_takes_every_row_of_its_config
    config = { "app" => { "windows" => [{ "label" => "fixed", "resizable" => false, "userAgent" => "Fixed" }] } }
    run_test_app(config:)

    assert_equal [false], StubNative.windows.map { |window| window.attributes[:resizable] }
    assert_equal ["Fixed"], StubNative.webviews.map { |webview| webview.attributes[:user_agent] }
  end

  # A parent named in the config must be built before the window that
  # names it, as in Tauri, whose from_config looks it up at once
  # (window/mod.rs:267-272).
  def test_a_configured_parent_is_found_among_the_windows_built_before_it
    windows = [{ "label" => "owner" }, { "label" => "child", "parent" => "owner" }]
    run_test_app(config: { "app" => { "windows" => windows } })

    owner, child = StubNative.windows
    assert_same owner, child.attributes[:parent]
  end

  def test_a_configured_parent_built_later_ends_run_with_window_not_found
    windows = [{ "label" => "child", "parent" => "owner" }, { "label" => "owner" }]
    app = build_test_app(config: { "app" => { "windows" => windows } })
    error = assert_raises(Tokra::Error::WindowNotFound) { app.run }

    assert_equal "window not found", error.message
    assert_empty StubNative.windows
  end
end
