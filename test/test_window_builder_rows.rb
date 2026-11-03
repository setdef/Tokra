# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "support/stub_native"

# The rows of WindowBuilder and WebviewWindowBuilder reach the native
# window and webview as Tauri's reach tao and wry (plan 052, phase 3):
# Tauri's defaults, each row's key, the size constraints in call order,
# the menu and its listener, the effects before window-created, the
# parent's native, and the platform-only rows only on their platform
# (window/mod.rs:429-906; webview_window.rs:452-897, 1073-1185;
# tauri-runtime-wry lib.rs:813-1260, 4318-4436).
class TestWindowBuilderRows < Minitest::Test
  MACOS = Tokra::App.os_name == "macos"
  WINDOWS = Tokra::App.os_name == "windows"
  LINUX = Tokra::App.os_name == "linux"

  # The Hash a builder with no rows hands Native::Window#open: Tauri's
  # WindowBuilder::new over tao's defaults.
  DEFAULTS = {
    title: "Tokra",
    inner_size: nil,
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
    shadow: nil,
    parent: nil,
    drag_and_drop: true,
    title_bar_style: "Visible",
    hidden_title: false,
    tabbing_identifier: nil,
    theme: nil,
    background_color: nil,
  }.freeze

  # What Native::WebView#open is handed with no rows, as Tauri's
  # WebviewAttributes start (tauri-runtime webview.rs:482-526); its rows
  # are test_webview_builder_rows.rb's.
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

  # Runs an app and calls the block on the main thread once it is Ready,
  # with the handle and a log; +events+ and then +tasks+ TaskEvents follow.
  def run_app(tasks: 0, events: [], &on_ready)
    log = []
    app = Tokra::Builder.default.build(native: StubNative)
    StubNative.inject_event(events + Array.new(tasks) { Tokra::Native::TaskEvent.new })
    app.run { |handle, event| on_ready&.call(handle, log) if event.is_a?(Tokra::RunEvent::Ready) }
    log
  end

  # Builds the webview window "side" with +rows+ applied, and answers its
  # native window and webview.
  def build_side(&rows)
    natives = nil
    run_app do |handle|
      builder = Tokra::WebviewWindowBuilder.new(handle, "side", page)
      returned = rows ? rows.call(builder, handle) : builder
      assert_same builder, returned, "a row answers the builder"
      built = builder.build
      natives = [built.window.native, built.webview.native]
    end
    natives
  end

  def test_a_builder_with_no_rows_hands_the_native_tauris_defaults
    window, webview = build_side

    assert_equal DEFAULTS, window.attributes
    assert_equal WEBVIEW_DEFAULTS, webview.attributes
  end

  def test_main_is_built_with_tauris_defaults_and_its_builders_title_and_size
    run_app

    main = StubNative.windows.first
    assert_equal DEFAULTS.merge(inner_size: [800.0, 600.0]), main.attributes
  end

  # Each row, the key it sets, and the value the native gets.
  def common_rows(handle)
    image = Tokra::Image.new(rgba: "\xFF".b * 16, width: 2, height: 2)
    [
      [:title, ["Side"], :title, "Side"],
      [:inner_size, [320, 240], :inner_size, [320.0, 240.0]],
      [:position, [10, 20.5], :position, [10.0, 20.5]],
      [:center, [], :center, true],
      [:prevent_overflow, [], :prevent_overflow, [true, 0.0, 0.0]],
      [:prevent_overflow_with_margin, [Tokra::LogicalSize.new(width: 8, height: 4)], :prevent_overflow, [false, 8.0, 4.0]],
      [:prevent_overflow_with_margin, [Tokra::PhysicalSize.new(width: 16, height: 9)], :prevent_overflow, [true, 16.0, 9.0]],
      [:resizable, [false], :resizable, false],
      [:maximizable, [false], :maximizable, false],
      [:minimizable, [false], :minimizable, false],
      [:closable, [false], :closable, false],
      [:fullscreen, [true], :fullscreen, true],
      [:focused, [false], :focused, false],
      [:focusable, [false], :focusable, false],
      [:maximized, [true], :maximized, true],
      [:visible, [false], :visible, false],
      [:decorations, [false], :decorations, false],
      [:always_on_bottom, [true], :always_on_bottom, true],
      [:always_on_top, [true], :always_on_top, true],
      [:visible_on_all_workspaces, [true], :visible_on_all_workspaces, true],
      [:content_protected, [true], :content_protected, true],
      [:skip_taskbar, [true], :skip_taskbar, true],
      [:window_classname, ["Side Class"], :window_classname, "Side Class"],
      [:shadow, [false], :shadow, false],
      [:theme, [Tokra::Theme::Dark], :theme, "Dark"],
      [:theme, [nil], :theme, nil],
      [:background_color, [Tokra::Color.new(red: 1, green: 2, blue: 3, alpha: 4)], :background_color, [1, 2, 3, 4]],
      [:icon, [image], :icon, Tokra::Native::Icon],
      [:parent, [handle.get_webview_window("main")], :parent, handle.get_window("main").native],
    ]
  end

  def test_each_row_reaches_its_key
    results = []
    run_app do |handle|
      common_rows(handle).each_with_index do |(row, args, key, expected), index|
        builder = Tokra::WebviewWindowBuilder.new(handle, "row-#{index}", page)
        assert_same builder, builder.public_send(row, *args), "#{row} answers the builder"
        native = builder.build.window.native
        results << [row, args, key, expected, native.attributes]
      end
    end

    results.each do |row, args, key, expected, attributes|
      if expected.is_a?(Module)
        assert_kind_of expected, attributes[key], "#{row}(#{args.inspect})"
      elsif expected.nil?
        assert_nil attributes[key], "#{row}(#{args.inspect})"
      else
        assert_equal expected, attributes[key], "#{row}(#{args.inspect})"
      end
      assert_equal DEFAULTS.except(key), attributes.except(key), "#{row} changes only #{key}"
    end
  end

  def test_a_boolean_row_reads_its_argument_as_ruby_does
    window, webview = build_side { |builder| builder.resizable(nil).decorations("yes").focused(nil) }

    assert_equal [false, true, false], window.attributes.values_at(:resizable, :decorations, :focused)
    assert_equal false, webview.attributes[:focused], "the webview's focus is read as Ruby reads it too"
  end

  def test_min_and_max_set_half_the_constraints_and_inner_size_constraints_replaces_all_four
    logical = -> (value) { [false, Float(value)] }
    first, = build_side { |builder| builder.min_inner_size(300, 200).max_inner_size(900, 700) }
    assert_equal [logical[300], logical[200], logical[900], logical[700]], first.attributes[:inner_size_constraints]

    constraints = Tokra::WindowSizeConstraints.new(min_width: Tokra::PhysicalUnit.new(640))
    StubNative.windows.clear
    second, = build_side { |builder| builder.min_inner_size(300, 200).inner_size_constraints(constraints).max_inner_size(900, 700) }
    assert_equal [[true, 640.0], nil, logical[900], logical[700]], second.attributes[:inner_size_constraints]
  end

  def test_the_webview_rows_of_a_webview_window_reach_the_webview_too
    color = Tokra::Color.new(red: 9, green: 8, blue: 7, alpha: 255)
    window, webview = build_side { |builder| builder.focused(false).background_color(color) }

    assert_equal [false, [9, 8, 7, 255]], window.attributes.values_at(:focused, :background_color)
    assert_equal WEBVIEW_DEFAULTS.merge(focused: false, background_color: [9, 8, 7, 255]), webview.attributes
  end

  def test_focus_focuses_both_and_warns_as_deprecated_naming_the_method_called
    deprecated = Warning[:deprecated]
    Warning[:deprecated] = true
    window = webview = nil
    _, stderr = capture_io do
      window, webview = build_side { |builder| builder.focused(false).focus }
    end

    assert_equal [true, true], [window.attributes[:focused], webview.attributes[:focused]]
    assert_includes stderr, "Tokra::WebviewWindowBuilder#focus is deprecated. The window is automatically focused " \
      "by default. This function Will be removed in 3.0.0. Use `focused` instead."
    refute_includes stderr, "Tokra::WindowBuilder#focus"
  ensure
    Warning[:deprecated] = deprecated
  end

  def test_focus_is_quiet_while_deprecation_warnings_are_off
    deprecated = Warning[:deprecated]
    Warning[:deprecated] = false
    _, stderr = capture_io { build_side { |builder, _handle| builder.focus } }

    assert_empty stderr
  ensure
    Warning[:deprecated] = deprecated
  end

  def test_a_typed_row_raises_type_error_on_the_calling_thread
    raised = []
    run_app do |handle|
      builder = Tokra::WebviewWindowBuilder.new(handle, "side", page)
      {
        title: [3],
        window_classname: [:side],
        theme: ["Dark"],
        background_color: ["#fff"],
        icon: ["icon.png"],
        menu: ["File"],
        effects: [[]],
        inner_size_constraints: [{ min_width: 1 }],
        prevent_overflow_with_margin: [[1, 2]],
        parent: [handle.get_window("main")],
      }.each do |row, args|
        raised << [row, assert_raises(TypeError, row.to_s) { builder.public_send(row, *args) }.class]
      end
      assert_raises(ArgumentError) { builder.position("left", 0) }
      assert_raises(TypeError) { builder.min_inner_size(nil, 0) }
    end

    assert_equal 10, raised.size
  end

  def test_a_bad_icon_raises_invalid_icon_and_builds_nothing
    error = nil
    run_app do |handle|
      bad = Tokra::Image.new(rgba: "\xFF".b * 3, width: 2, height: 2)
      error = assert_raises(Tokra::Error::Runtime) { Tokra::WebviewWindowBuilder.new(handle, "side", page).icon(bad) }
    end

    assert_match(/\Aruntime error: invalid icon: /, error.message)
    assert_equal ["main"], StubNative.windows.map(&:label)
  end

  # Runs an app on StubWindowMenusNative, whose windows hold their own
  # menu bars, as on Windows and Linux.
  def run_menu_app(&on_ready)
    app = Tokra::Builder.default.build(native: StubWindowMenusNative)
    app.run { |handle, event| on_ready.call(handle) if event.is_a?(Tokra::RunEvent::Ready) }
  end

  def save_menu(handle) = Tokra::Menu::MenuBuilder.with_id(handle, "side-menu").text("save", "Save").build

  def test_the_builders_menu_is_the_windows_own_and_takes_the_builders_theme
    menu = window = nil
    run_menu_app do |handle|
      menu = save_menu(handle)
      window = Tokra::WebviewWindowBuilder.new(handle, "side", page).theme(Tokra::Theme::Dark).menu(menu).build.window
    end

    assert_same menu, window.menu
    refute window.has_app_wide_menu?, "a builder's menu is the window's own"
    assert_includes handle_menus(window), "side-menu"
    assert_equal [[:init_menu, "side-menu"]], window.native.menu_calls
    assert_equal ["Dark"], window.native.menu_themes, "Tauri themes the menu bar with the builder's theme"
  end

  def test_without_a_theme_the_menu_bar_takes_auto
    window = nil
    run_menu_app do |handle|
      window = Tokra::WebviewWindowBuilder.new(handle, "side", page).menu(save_menu(handle)).build.window
    end

    assert_equal ["Auto"], window.native.menu_themes
  end

  def handle_menus(window) = window.app_handle.menu_manager.menus.map { |menu| menu.id.to_s }

  def test_on_menu_event_makes_the_block_the_windows_menu_listener
    heard = []
    run_app(events: [Tokra::Native::MenuEvent.new("save")]) do |handle|
      Tokra::WebviewWindowBuilder.new(handle, "side", page)
        .on_menu_event { |source, event| heard << [source.label, event.id.to_s] }.build
    end

    assert_equal [["side", "save"]], heard
  end

  def test_effects_set_before_window_created_in_the_main_thread_task
    effects = Tokra::EffectsBuilder.new.effect(Tokra::Effect::Mica).build
    log = run_app(tasks: 4) do |handle, recorded|
      handle.listen_any("tauri://window-created") { |event| recorded << [:created, event.payload] }
      Thread.new do
        window = Tokra::WebviewWindowBuilder.new(handle, "side", page).effects(effects).build.window
        native = window.native
        native.define_singleton_method(:set_effects) do |config|
          recorded << [:set_effects, config]
          super(config)
        end
      end.join
    end

    assert_equal [[:set_effects, [["Mica"], nil, nil, nil]], [:created, '{"label":"side"}']], log
  end

  def test_a_failing_effect_is_dropped_as_tauri_drops_it
    effects = Tokra::EffectsBuilder.new.effect(Tokra::Effect::Mica).build
    log = run_app(tasks: 4) do |handle, recorded|
      handle.listen_any("tauri://window-created") { |event| recorded << [:created, event.payload] }
      Thread.new do
        native = Tokra::WebviewWindowBuilder.new(handle, "side", page).effects(effects).build.window.native
        native.define_singleton_method(:set_effects) { |_config| raise "no effects here" }
      end.join
    end

    assert_equal [[:created, '{"label":"side"}']], log
  end

  def test_a_parent_must_be_open
    error = nil
    run_app do |handle|
      main = handle.get_webview_window("main")
      main.window.native.close
      error = assert_raises(Tokra::Error::Runtime) { Tokra::WebviewWindowBuilder.new(handle, "side", page).parent(main) }
    end

    assert_equal "runtime error: #{Tokra::Error::Runtime::FAILED_TO_RECEIVE_MESSAGE}", error.message
  end

  def test_the_window_builder_takes_a_window_as_its_parent
    attributes = nil
    run_app do |handle|
      builder = Tokra::WindowBuilder.new(handle, "bare")
      assert_same builder, builder.parent(handle.get_window("main"))
      assert_raises(TypeError) { builder.parent(handle.get_webview_window("main")) }
      attributes = builder.native_attributes
    end

    assert_same StubNative.windows.first, attributes[:parent]
  end

  def test_the_platform_only_rows_exist_only_on_their_platform
    {
      title_bar_style: MACOS,
      hidden_title: MACOS,
      tabbing_identifier: MACOS,
      owner: WINDOWS,
      drag_and_drop: WINDOWS,
      transient_for: LINUX,
      transparent: !MACOS,
    }.each do |row, defined|
      assert_equal defined, Tokra::WindowBuilder.method_defined?(row), "WindowBuilder##{row}"
      assert_equal defined, Tokra::WebviewWindowBuilder.method_defined?(row), "WebviewWindowBuilder##{row}"
    end
    assert_equal MACOS, Tokra::WebviewWindowBuilder.method_defined?(:traffic_light_position)
    refute Tokra::WindowBuilder.method_defined?(:traffic_light_position), "only the webview window has it"
  end

  def test_on_macos_the_title_bar_rows_reach_the_window_and_the_traffic_lights_the_webview
    skip "Tauri's title bar rows are macOS only" unless MACOS
    window, webview = build_side do |builder|
      builder.title_bar_style(Tokra::TitleBarStyle::Overlay).hidden_title(true).tabbing_identifier("docs")
        .traffic_light_position(Tokra::LogicalPosition.new(x: 12, y: 18))
    end

    assert_equal ["Overlay", true, "docs"], window.attributes.values_at(:title_bar_style, :hidden_title, :tabbing_identifier)
    assert_equal [false, 12.0, 18.0], webview.attributes[:traffic_light_position]
    assert_equal DEFAULTS.except(:title_bar_style, :hidden_title, :tabbing_identifier),
      window.attributes.except(:title_bar_style, :hidden_title, :tabbing_identifier)
    run_app do |handle|
      builder = Tokra::WebviewWindowBuilder.new(handle, "typed", page)
      assert_raises(TypeError) { builder.title_bar_style("Overlay") }
      assert_raises(TypeError) { builder.tabbing_identifier(:docs) }
      assert_raises(TypeError) { builder.traffic_light_position([1, 2]) }
    end
  end

  def test_on_windows_the_owner_and_drag_and_drop_rows_reach_the_window
    skip "Tauri's owner and drag_and_drop are Windows only" unless WINDOWS
    main = nil
    window, = build_side do |builder, handle|
      main = handle.get_window("main").native
      builder.owner(handle.get_webview_window("main")).drag_and_drop(false)
    end

    assert_same main, window.attributes[:parent]
    refute window.attributes[:drag_and_drop]
  end

  def test_on_linux_transient_for_reaches_the_window
    skip "Tauri's transient_for is Linux only" unless LINUX
    main = nil
    window, = build_side do |builder, handle|
      main = handle.get_window("main").native
      builder.transient_for(handle.get_webview_window("main"))
    end

    assert_same main, window.attributes[:parent]
  end

  def test_off_macos_transparent_makes_the_window_and_its_webview_transparent
    skip "transparent waits on macos-private-api on macOS (plan 052, question 2)" if MACOS
    window, webview = build_side { |builder| builder.transparent(true) }

    assert window.attributes[:transparent]
    assert webview.attributes[:transparent]
  end
end
