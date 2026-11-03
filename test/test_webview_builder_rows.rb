# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "support/stub_native"

# The webview rows of WebviewWindowBuilder reach the native webview as
# Tauri's reach wry (plan 052, 052e-1): WebviewAttributes::new's defaults,
# each row's key, the builder's scripts after Tauri's with their frames,
# the proxy as parse_proxy_url reads it, and the platform-only rows only on
# their platform (webview/mod.rs:816-1203; webview_window.rs:857-862,
# 900-1231; tauri-runtime webview.rs:482-526; tauri-runtime-wry
# lib.rs:4301-4316, 4556-4961).
class TestWebviewBuilderRows < Minitest::Test
  MACOS = Tokra::App.os_name == "macos"
  WINDOWS = Tokra::App.os_name == "windows"

  # What Native::WebView#open is handed with no rows, besides the URL and
  # the scripts: Tauri's WebviewAttributes::new.
  WEBVIEW_DEFAULTS = {
    focused: true,
    transparent: false,
    background_color: nil,
    traffic_light_position: nil,
    accept_first_mouse: false,
    user_agent: nil,
    additional_browser_args: nil,
    drag_drop_handler_enabled: true,
    clipboard: false,
    incognito: false,
    proxy_url: nil,
    browser_extensions_enabled: false,
    extensions_path: nil,
    data_store_identifier: nil,
    background_throttling: nil,
    javascript_disabled: false,
    scroll_bar_style: "Default",
    allow_link_preview: true,
  }.freeze

  def page = Tokra::WebviewUrl::App.new("index.html")

  # Runs an app and calls the block on the main thread once it is Ready.
  def run_app(&on_ready)
    app = Tokra::Builder.default.build(native: StubNative)
    app.run { |handle, event| on_ready&.call(handle) if event.is_a?(Tokra::RunEvent::Ready) }
  end

  # Builds the webview window "side" with +rows+ applied, and answers its
  # native webview.
  def build_side(&rows)
    native = nil
    run_app do |handle|
      builder = Tokra::WebviewWindowBuilder.new(handle, "side", page)
      returned = rows ? rows.call(builder, handle) : builder
      assert_same builder, returned, "a row answers the builder"
      native = builder.build.webview.native
    end
    native
  end

  def test_a_builder_with_no_rows_hands_the_webview_tauris_defaults
    assert_equal WEBVIEW_DEFAULTS, build_side.attributes
  end

  def test_main_is_built_with_tauris_webview_defaults
    run_app

    assert_equal WEBVIEW_DEFAULTS, StubNative.webviews.first.attributes
  end

  # Each row, its arguments, the key it sets, and the value the native gets.
  def common_rows
    [
      [:accept_first_mouse, [true], :accept_first_mouse, true],
      [:user_agent, ["Probe/1.0"], :user_agent, "Probe/1.0"],
      [:additional_browser_args, ["--disable-gpu"], :additional_browser_args, "--disable-gpu"],
      [:disable_drag_drop_handler, [], :drag_drop_handler_enabled, false],
      [:enable_clipboard_access, [], :clipboard, true],
      [:incognito, [true], :incognito, true],
      [:proxy_url, [URI("http://proxy.test:3128")], :proxy_url, ["http", "proxy.test", "3128"]],
      [:browser_extensions_enabled, [true], :browser_extensions_enabled, true],
      [:extensions_path, ["/opt/extensions"], :extensions_path, "/opt/extensions"],
      [:extensions_path, [Pathname("/opt/extensions")], :extensions_path, "/opt/extensions"],
      [:data_store_identifier, [(0..15).to_a], :data_store_identifier, (0..15).to_a],
      [:background_throttling, [Tokra::BackgroundThrottlingPolicy::Disabled], :background_throttling, "Disabled"],
      [:background_throttling, [Tokra::BackgroundThrottlingPolicy::Suspend], :background_throttling, "Suspend"],
      [:background_throttling, [Tokra::BackgroundThrottlingPolicy::Throttle], :background_throttling, "Throttle"],
      [:disable_javascript, [], :javascript_disabled, true],
      [:scroll_bar_style, [Tokra::ScrollBarStyle::Default], :scroll_bar_style, "Default"],
      [:focused, [false], :focused, false],
    ]
  end

  def test_each_row_reaches_its_key
    results = []
    run_app do |handle|
      common_rows.each_with_index do |(row, args, key, expected), index|
        builder = Tokra::WebviewWindowBuilder.new(handle, "row-#{index}", page)
        assert_same builder, builder.public_send(row, *args), "#{row} answers the builder"
        results << [row, args, key, expected, builder.build.webview.native.attributes]
      end
    end

    results.each do |row, args, key, expected, attributes|
      assert_equal expected, attributes[key], "#{row}(#{args.inspect})"
      assert_equal WEBVIEW_DEFAULTS.except(key), attributes.except(key), "#{row} changes only #{key}"
    end
  end

  def test_a_boolean_row_reads_its_argument_as_ruby_does
    attributes = build_side { |builder| builder.accept_first_mouse("yes").incognito(nil).browser_extensions_enabled(1) }
      .attributes

    assert_equal [true, false, true], attributes.values_at(:accept_first_mouse, :incognito, :browser_extensions_enabled)
  end

  def test_the_builders_scripts_follow_tauris_in_call_order_with_their_frames
    side = build_side do |builder|
      builder.initialization_script("first()").initialization_script_for_all_frames("every()")
        .initialization_script("last()")
    end
    main = StubNative.webviews.first

    assert main.initialization_script_pairs.all? { |_script, main_only| main_only == true },
      "Tauri's own scripts run in the main frame only"
    tauri = side.initialization_script_pairs.first(main.initialization_script_pairs.size)
    assert_includes tauri.map(&:first).join, 'currentWebview: { label: "side" }'
    assert_equal [["first()", true], ["every()", false], ["last()", true]],
      side.initialization_script_pairs.drop(tauri.size), "the builder's scripts follow, in call order"
  end

  def test_a_proxy_url_reaches_the_webview_as_parse_proxy_url_reads_it
    cases = {
      "http://Proxy.Test:3128" => ["http", "proxy.test", "3128"],
      "http://proxy.test" => ["http", "proxy.test", ""],
      "http://proxy.test:80" => ["http", "proxy.test", ""],
      "http://[::1]:8080" => ["http", "[::1]", "8080"],
      "socks5://Proxy.Test:1080" => ["socks5", "Proxy.Test", "1080"],
      "socks5://proxy.test" => ["socks5", "proxy.test", ""],
    }
    got = {}
    run_app do |handle|
      cases.each_key.with_index do |url, index|
        got[url] = Tokra::WebviewWindowBuilder.new(handle, "proxy-#{index}", page).proxy_url(URI(url)).build
          .webview.native.attributes[:proxy_url]
      end
    end

    assert_equal cases, got
  end

  def test_a_proxy_url_of_another_scheme_fails_the_webview_as_tauri_logs_it
    built = nil
    assert_output(nil, "Invalid proxy url\n") do
      run_app do |handle|
        built = Tokra::WebviewWindowBuilder.new(handle, "side", page).proxy_url(URI("https://proxy.test:3128")).build
      end
    end

    assert built.window.native.discarded?, "the window goes with its webview, as a failed webview's does"
    refute built.webview.native.opened?, "the webview is never built"
  end

  def test_a_typed_row_raises_on_the_calling_thread
    raised = []
    run_app do |handle|
      builder = Tokra::WebviewWindowBuilder.new(handle, "side", page)
      {
        initialization_script: [3],
        initialization_script_for_all_frames: [nil],
        user_agent: [:probe],
        additional_browser_args: [1],
        proxy_url: ["http://proxy.test:3128"],
        extensions_path: [3],
        data_store_identifier: ["0123456789abcdef"],
        background_throttling: ["Disabled"],
        scroll_bar_style: [:Default],
      }.each do |row, args|
        assert_raises(TypeError, row.to_s) { builder.public_send(row, *args) }
        raised << row
      end
      assert_raises(TypeError) { builder.data_store_identifier([1.0] * 16) }
      assert_raises(ArgumentError) { builder.data_store_identifier([0] * 15) }
      assert_raises(ArgumentError) { builder.data_store_identifier(([0] * 15) + [256]) }
      assert_raises(ArgumentError) { builder.data_store_identifier([-1] + ([0] * 15)) }
      builder.build
    end

    assert_equal 9, raised.size
    assert_equal WEBVIEW_DEFAULTS, StubNative.webviews.last.attributes, "a refused row sets nothing"
  end

  def test_the_window_rows_that_touch_the_webview_go_through_the_webview_builder
    color = Tokra::Color.new(red: 9, green: 8, blue: 7, alpha: 255)
    attributes = build_side { |builder| builder.focused(false).background_color(color) }.attributes

    assert_equal WEBVIEW_DEFAULTS.merge(focused: false, background_color: [9, 8, 7, 255]), attributes
  end

  def test_the_webview_builder_holds_its_label_url_and_rows
    url = Tokra::WebviewUrl::App.new("pane.html")
    builder = Tokra::WebviewBuilder.new("pane", url)
    assert_same builder, builder.user_agent("Pane/1").initialization_script("pane()")

    assert_equal "pane", builder.label
    assert_same url, builder.url
    assert_equal WEBVIEW_DEFAULTS.merge(user_agent: "Pane/1"), builder.native_attributes
    assert_equal [["pane()", true]], builder.initialization_scripts
    assert_raises(TypeError) { Tokra::WebviewBuilder.new(:pane, url) }
  end

  def test_the_platform_only_rows_exist_only_on_their_platform
    assert_equal MACOS, Tokra::WebviewWindowBuilder.method_defined?(:allow_link_preview)
    assert_equal MACOS, Tokra::WebviewBuilder.method_defined?(:allow_link_preview)
    assert_equal !MACOS, Tokra::WebviewBuilder.method_defined?(:transparent)
    refute Tokra::WebviewBuilder.method_defined?(:traffic_light_position), "only the webview window has the row"
    assert_equal WINDOWS, Tokra::ScrollBarStyle.const_defined?(:FluentOverlay, false)
  end

  def test_on_macos_allow_link_preview_reaches_the_webview
    skip "Tauri's allow_link_preview is macOS only" unless MACOS
    attributes = build_side { |builder| builder.allow_link_preview(nil) }.attributes

    assert_equal WEBVIEW_DEFAULTS.merge(allow_link_preview: false), attributes
  end

  def test_on_windows_fluent_overlay_reaches_the_webview
    skip "Tauri's FluentOverlay is Windows only" unless WINDOWS
    attributes = build_side { |builder| builder.scroll_bar_style(Tokra::ScrollBarStyle.const_get(:FluentOverlay)) }
      .attributes

    assert_equal "FluentOverlay", attributes[:scroll_bar_style]
  end

  def test_the_policies_and_styles_are_closed
    assert_equal %w[Disabled Suspend Throttle], Tokra::BackgroundThrottlingPolicy.constants.sort.map(&:to_s)
    assert_raises(NoMethodError) { Tokra::BackgroundThrottlingPolicy.new(name: "Off") }
    assert_raises(NoMethodError) { Tokra::ScrollBarStyle.new(name: "Thin") }
  end
end
