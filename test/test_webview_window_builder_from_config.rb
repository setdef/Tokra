# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "support/stub_native"
require_relative "support/test_app"

# WebviewWindowBuilder.from_config builds a window from one entry of the
# config's app.windows as Tauri's does (plan 054, decision 15): the window
# rows tauri-runtime-wry's WindowBuilderWrapper::with_config sets
# (lib.rs:837-948), the effects and the parent WindowBuilder::from_config
# takes (window/mod.rs:250-275), and the webview rows of
# WebviewAttributes::from (tauri-runtime webview.rs:421-478). Each test
# reads what reaches StubNative's window and webview.
class TestWebviewWindowBuilderFromConfig < Minitest::Test
  MACOS = Tokra::App.os_name == "macos"
  WINDOWS = Tokra::App.os_name == "windows"

  # The window attributes from_config hands the native for a config entry
  # that sets nothing: Tauri's WindowBuilder::new defaults, with the
  # config's title and size, its shadow on, and tao's cursor-moved event
  # off (lib.rs:871-881, 885-904).
  DEFAULT_WINDOW = {
    title: "Tokra App",
    inner_size: [800.0, 600.0],
    position: nil,
    inner_size_constraints: [nil, nil, nil, nil],
    center: false,
    prevent_overflow: nil,
    resizable: true,
    maximizable: true,
    minimizable: true,
    closable: true,
    fullscreen: false,
    focused: true,
    focusable: true,
    maximized: false,
    visible: true,
    transparent: false,
    decorations: true,
    always_on_bottom: false,
    always_on_top: false,
    visible_on_all_workspaces: false,
    content_protected: false,
    icon: nil,
    skip_taskbar: false,
    window_classname: "Tokra Window",
    shadow: true,
    parent: nil,
    drag_and_drop: true,
    title_bar_style: "Visible",
    hidden_title: false,
    tabbing_identifier: nil,
    theme: nil,
    background_color: nil,
    cursor_moved_event: false,
  }.freeze

  # The webview attributes for that entry: WebviewAttributes::new's, which
  # WebviewAttributes::from leaves as they are for the config's defaults.
  DEFAULT_WEBVIEW = {
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

  def window_config(json) = Tokra::Utils::Config::WindowConfig.deserialize({ "label" => "side" }.merge(json))

  # Runs an app and calls the block on the main thread once it is Ready,
  # with the handle; +tasks+ TaskEvents follow, each running one queued
  # task.
  def run_app(tasks: 0, &on_ready)
    # Without a default window icon, as Tauri's mock context has none
    # (test/mod.rs:130), so the icon row keeps tao's default.
    context = build_test_context
    context.set_default_window_icon(nil)
    app = Tokra::Builder.default.build(context, native: StubNative)
    StubNative.inject_event(Array.new(tasks) { Tokra::Native::TaskEvent.new })
    app.run { |handle, event| on_ready&.call(handle) if event.is_a?(Tokra::RunEvent::Ready) }
  end

  # The native window and webview from_config builds for +json+, a
  # WindowConfig's JSON with the label "side".
  def build_side(json = {})
    natives = nil
    run_app do |handle|
      built = Tokra::WebviewWindowBuilder.from_config(handle, window_config(json)).build
      natives = [built.window.native, built.webview.native]
    end
    natives
  end

  def test_an_entry_that_sets_nothing_hands_the_native_tauris_config_defaults
    window, webview = build_side

    assert_equal "side", window.label
    assert_equal DEFAULT_WINDOW, window.attributes
    assert_equal DEFAULT_WEBVIEW, webview.attributes
  end

  # Each config key, its JSON, the window attribute it sets, and the value
  # the native gets: with_config's rows, in its order.
  WINDOW_ROWS = [
    ["title", "Side", :title, "Side"],
    ["width", 320, :inner_size, [320.0, 600.0]],
    ["height", 240, :inner_size, [800.0, 240.0]],
    ["focus", false, :focused, false],
    ["focusable", false, :focusable, false],
    ["visible", false, :visible, false],
    ["resizable", false, :resizable, false],
    ["fullscreen", true, :fullscreen, true],
    ["decorations", false, :decorations, false],
    ["maximized", true, :maximized, true],
    ["alwaysOnBottom", true, :always_on_bottom, true],
    ["alwaysOnTop", true, :always_on_top, true],
    ["visibleOnAllWorkspaces", true, :visible_on_all_workspaces, true],
    ["contentProtected", true, :content_protected, true],
    ["skipTaskbar", true, :skip_taskbar, true],
    ["theme", "Dark", :theme, "Dark"],
    ["closable", false, :closable, false],
    ["maximizable", false, :maximizable, false],
    ["minimizable", false, :minimizable, false],
    ["shadow", false, :shadow, false],
    ["minWidth", 300, :inner_size_constraints, [[false, 300.0], nil, nil, nil]],
    ["minHeight", 200, :inner_size_constraints, [nil, [false, 200.0], nil, nil]],
    ["maxWidth", 900, :inner_size_constraints, [nil, nil, [false, 900.0], nil]],
    ["maxHeight", 700, :inner_size_constraints, [nil, nil, nil, [false, 700.0]]],
    ["backgroundColor", "#01020304", :background_color, [1, 2, 3, 4]],
    ["center", true, :center, true],
    ["windowClassname", "Side Class", :window_classname, "Side Class"],
    ["preventOverflow", true, :prevent_overflow, [true, 0.0, 0.0]],
    ["preventOverflow", false, :prevent_overflow, nil],
    ["preventOverflow", { "width" => 16, "height" => 9 }, :prevent_overflow, [true, 16.0, 9.0]],
  ].freeze

  def test_each_window_row_reaches_its_attribute
    results = []
    run_app do |handle|
      WINDOW_ROWS.each_with_index do |(key, value, attribute, expected), index|
        config = window_config({ "label" => "row-#{index}", key => value })
        native = Tokra::WebviewWindowBuilder.from_config(handle, config).build.window.native
        results << [key, value, attribute, expected, native.attributes]
      end
    end

    results.each do |key, value, attribute, expected, attributes|
      message = "#{key}: #{value.inspect}"
      expected.nil? ? assert_nil(attributes[attribute], message) : assert_equal(expected, attributes[attribute], message)
      assert_equal DEFAULT_WINDOW.except(attribute), attributes.except(attribute), "#{key} changes only #{attribute}"
    end
  end

  # tao takes a position only with both coordinates (lib.rs:925-927).
  def test_a_position_needs_both_x_and_y
    positions = []
    run_app do |handle|
      [{ "x" => 10, "y" => 20.5 }, { "x" => 10 }, { "y" => 20 }].each_with_index do |json, index|
        config = window_config(json.merge("label" => "at-#{index}"))
        positions << Tokra::WebviewWindowBuilder.from_config(handle, config).build.window.native.attributes[:position]
      end
    end

    assert_equal [[10.0, 20.5], nil, nil], positions
  end

  # Each config key, its JSON, the webview attribute it sets, and the
  # value the native gets: WebviewAttributes::from's rows, in its order.
  WEBVIEW_ROWS = [
    ["incognito", true, :incognito, true],
    ["focus", false, :focused, false],
    ["browserExtensionsEnabled", true, :browser_extensions_enabled, true],
    ["backgroundThrottling", "disabled", :background_throttling, "Disabled"],
    ["scrollBarStyle", "fluentOverlay", :scroll_bar_style, WINDOWS ? "FluentOverlay" : "Default"],
    ["acceptFirstMouse", true, :accept_first_mouse, true],
    ["dragDropEnabled", false, :drag_drop_handler_enabled, false],
    ["userAgent", "Side Agent", :user_agent, "Side Agent"],
    ["additionalBrowserArgs", "--side", :additional_browser_args, "--side"],
    ["proxyUrl", "socks5://127.0.0.1:1080", :proxy_url, ["socks5", "127.0.0.1", "1080"]],
    ["backgroundColor", "#01020304", :background_color, [1, 2, 3, 4]],
    ["javascriptDisabled", true, :javascript_disabled, true],
    ["allowLinkPreview", false, :allow_link_preview, false],
  ].freeze

  def test_each_webview_row_reaches_its_attribute
    results = []
    run_app do |handle|
      WEBVIEW_ROWS.each_with_index do |(key, value, attribute, expected), index|
        config = window_config({ "label" => "row-#{index}", key => value })
        native = Tokra::WebviewWindowBuilder.from_config(handle, config).build.webview.native
        results << [key, value, attribute, expected, native.attributes]
      end
    end

    results.each do |key, value, attribute, expected, attributes|
      assert_equal expected, attributes[attribute], "#{key}: #{value.inspect}"
      assert_equal DEFAULT_WEBVIEW.except(attribute), attributes.except(attribute), "#{key} changes only #{attribute}"
    end
  end

  def test_the_webview_loads_the_configs_url
    url = nil
    run_app do |handle|
      config = window_config({ "url" => "https://example.com/side" })
      url = Tokra::WebviewWindowBuilder.from_config(handle, config).build.webview.native.url
    end

    assert_equal "https://example.com/side", url
  end

  # Keys whose row Tokra does not have yet (plan 054's inventory), and
  # those Tauri's from_config itself never reads: dataStoreIdentifier,
  # which WebviewAttributes::from leaves out (webview.rs:421-478), and
  # disableInputAccessoryView, which is iOS's.
  def test_the_keys_that_wait_for_their_row_change_nothing
    waiting = {
      "zoomHotkeysEnabled" => true,
      "useHttpsScheme" => true,
      "devtools" => false,
      "dataDirectory" => "side",
      "dataStoreIdentifier" => Array.new(16, 7),
      "disableInputAccessoryView" => true,
    }
    waiting["transparent"] = true if MACOS
    window, webview = build_side(waiting)

    assert_equal DEFAULT_WINDOW, window.attributes
    assert_equal DEFAULT_WEBVIEW, webview.attributes
  end

  def test_off_macos_transparent_makes_the_window_and_its_webview_transparent
    skip "transparent waits on macos-private-api on macOS (plan 052, question 2)" if MACOS
    window, webview = build_side({ "transparent" => true })

    assert window.attributes[:transparent]
    assert webview.attributes[:transparent]
  end

  def test_on_macos_the_title_bar_rows_reach_the_window_and_the_traffic_lights_the_webview
    skip "Tauri's title bar rows are macOS only" unless MACOS
    window, webview = build_side({
      "titleBarStyle" => "Overlay",
      "hiddenTitle" => true,
      "tabbingIdentifier" => "docs",
      "trafficLightPosition" => { "x" => 12, "y" => 18 },
    })

    assert_equal ["Overlay", true, "docs"], window.attributes.values_at(:title_bar_style, :hidden_title, :tabbing_identifier)
    assert_equal [false, 12.0, 18.0], webview.attributes[:traffic_light_position]
  end

  def test_off_macos_the_title_bar_keys_change_nothing
    skip "macOS reads the title bar keys" if MACOS
    window, webview = build_side({
      "titleBarStyle" => "Overlay",
      "hiddenTitle" => true,
      "tabbingIdentifier" => "docs",
      "trafficLightPosition" => { "x" => 12, "y" => 18 },
    })

    assert_equal DEFAULT_WINDOW, window.attributes
    assert_equal DEFAULT_WEBVIEW, webview.attributes
  end

  # WindowBuilder::from_config takes the effects, which the window gets
  # once it exists (window/mod.rs:255, 411-424).
  def test_the_configs_effects_reach_the_window
    native = nil
    run_app(tasks: 1) do |handle|
      config = window_config({ "windowEffects" => { "effects" => ["mica"] } })
      native = Tokra::WebviewWindowBuilder.from_config(handle, config).build.window.native
    end

    assert_equal [[["Mica"], nil, nil, nil]], native.requests[:set_effects]
  end

  def test_a_parent_naming_a_window_makes_it_the_parent
    window, = build_side({ "parent" => "main" })

    assert_same StubNative.windows.first, window.attributes[:parent]
  end

  # Tauri's "window not found" (error.rs:136-138), raised by from_config
  # itself (window/mod.rs:267-272).
  def test_a_parent_naming_no_window_raises_window_not_found
    error = nil
    run_app do |handle|
      error = assert_raises(Tokra::Error::WindowNotFound) do
        Tokra::WebviewWindowBuilder.from_config(handle, window_config({ "parent" => "nowhere" }))
      end
    end

    assert_equal "window not found", error.message
    assert_kind_of Tokra::Error, error
    assert_equal ["main"], StubNative.windows.map(&:label)
  end

  def test_the_builder_from_config_takes_more_rows_before_build
    window = nil
    run_app do |handle|
      builder = Tokra::WebviewWindowBuilder.from_config(handle, window_config({ "title" => "Config" }))
      window = builder.title("Code").resizable(false).build.window.native
    end

    assert_equal ["Code", false], window.attributes.values_at(:title, :resizable)
  end

  def test_anything_but_a_window_config_raises_type_error
    run_app do |handle|
      error = assert_raises(TypeError) { Tokra::WebviewWindowBuilder.from_config(handle, { "label" => "side" }) }
      assert_equal "wrong argument type Hash (expected Tokra::Utils::Config::WindowConfig)", error.message
    end
  end

  # A builder made with new keeps tao's cursor-moved event, which only
  # with_config turns off (lib.rs:871-881).
  def test_a_builder_made_with_new_keeps_the_cursor_moved_event
    native = nil
    run_app do |handle|
      native = Tokra::WebviewWindowBuilder.new(handle, "side", Tokra::WebviewUrl::App.new("index.html")).build.window.native
    end

    assert native.attributes[:cursor_moved_event]
  end
end
