# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/stub_native"

# Tokra::Tray through a real App and AppHandle, with real muda menus and
# StubNative's tray, which records what tray-icon would be asked (plan 043).
class TestTray < Minitest::Test
  def setup
    @app = Tokra::Builder.default.build(native: StubNative)
    @handle = @app.handle
  end

  def teardown
    StubNative.clear_event
  end

  def image(red = 0x20)
    Tokra::Image.new(rgba: [red, 0x80, 0xE0, 0xFF].pack("C*") * 4, width: 2, height: 2)
  end

  def test_the_builder_hands_tray_icon_every_attribute_on_the_main_thread
    menu = Tokra::Menu::MenuBuilder.with_id(@handle, "tray-menu").text("open", "Open").build
    tray = Tokra::Tray::TrayIconBuilder.with_id("main")
      .menu(menu).icon(image).tooltip("Tip").title("Title").temp_dir_path(Pathname("/tmp/icons"))
      .icon_as_template(true).show_menu_on_left_click(false)
      .build(@app)

    native = StubNative::TrayIcon.instances.last
    assert_same native, tray.native
    assert_equal "main", native.id
    attributes = native.attributes
    assert_same menu.native, attributes["menu"]
    assert_instance_of Tokra::Native::TrayIcon::Icon, attributes["icon"]
    assert_equal ["Tip", "Title", "/tmp/icons", true, false],
      attributes.values_at("tooltip", "title", "temp_dir_path", "icon_is_template", "menu_on_left_click")
    assert native.built_on_main_thread?
  end

  def test_a_bare_builder_leaves_tray_icons_defaults
    Tokra::Tray::TrayIconBuilder.new.build(@app)

    assert_equal({
"menu" => nil,
"icon" => nil,
"tooltip" => nil,
"title" => nil,
"temp_dir_path" => nil,
"icon_is_template" => false,
"menu_on_left_click" => true,
},
      StubNative::TrayIcon.instances.last.attributes)
  end

  # TrayIconBuilder::new takes the next number from tray-icon's counter,
  # and with_id takes one too before it replaces it (tray/mod.rs:216-234).
  def test_a_new_builder_takes_tray_icons_next_id_and_with_id_takes_one_as_well
    first = Integer(Tokra::Tray::TrayIconBuilder.new.id.value)
    named = Tokra::Tray::TrayIconBuilder.with_id(:named)
    after = Integer(Tokra::Tray::TrayIconBuilder.new.id.value)

    assert_equal Tokra::Tray::TrayIconId.new(value: "named"), named.id
    assert_equal first + 2, after
  end

  # Tauri's builder drops an image tray-icon refuses, keeping the icon it
  # had (tray/mod.rs:252-258).
  def test_the_builder_drops_an_image_tray_icon_refuses_and_keeps_the_last_good_one
    bad = Tokra::Image.new(rgba: "\x00".b * 3, width: 1, height: 1)
    builder = Tokra::Tray::TrayIconBuilder.new.icon(image)
    kept = builder.instance_variable_get(:@icon)

    builder.icon(bad).build(@app)

    assert_same kept, StubNative::TrayIcon.instances.last.attributes["icon"]
  end

  def test_set_icon_raises_tray_icons_bad_icon_text_and_reaches_tray_icon_with_a_good_one
    tray = Tokra::Tray::TrayIconBuilder.new.build(@app)

    error = assert_raises(Tokra::Error::BadTrayIcon) do
      tray.set_icon(Tokra::Image.new(rgba: "\x00".b * 4, width: 65_536, height: 65_536))
    end
    assert_equal "The specified dimensions (65536x65536) don't match the number of pixels supplied by the `rgba` " \
      "argument (1). For those dimensions, the expected pixel count is 4294967296.", error.message
    assert_empty tray.native.calls

    tray.set_icon(image)
    tray.set_icon(nil)
    assert_equal [Tokra::Native::TrayIcon::Icon, NilClass], tray.native.calls.map { |(_, icon)| icon.class }
  end

  def test_a_tray_icon_error_is_error_tray_with_tauris_prefix
    StubNative::TrayIcon.fail_next = "not on the main thread"

    error = assert_raises(Tokra::Error::Tray) { Tokra::Tray::TrayIconBuilder.with_id("x").build(@app) }
    assert_equal "tray icon error: not on the main thread", error.message
    assert_nil @handle.tray_by_id("x"), "a tray that failed is not registered"
  end

  def test_a_builder_takes_only_a_menu_or_a_submenu
    item = Tokra::Menu::MenuItem.new(@handle, "Open", true, nil)

    error = assert_raises(TypeError) { Tokra::Tray::TrayIconBuilder.new.menu(item) }
    assert_equal "wrong argument type Tokra::Menu::MenuItem (expected Tokra::Menu::Menu or Tokra::Menu::Submenu)",
      error.message
    submenu = Tokra::Menu::Submenu.new(@handle, "More", true)
    Tokra::Tray::TrayIconBuilder.new.menu(submenu).build(@app)
    assert_same submenu.native, StubNative::TrayIcon.instances.last.attributes["menu"]
  end

  # register puts the tray in the app's table and its icons, and the
  # builder's menu listener among the app's (tray/mod.rs:421-456).
  def test_a_built_tray_is_in_the_apps_table_and_found_by_its_id
    heard = []
    tray = Tokra::Tray::TrayIconBuilder.with_id("main").on_menu_event { |_, event| heard << event.id.to_s }.build(@app)

    rid = @handle.tray_manager.tray_resource_by_id("main")
    assert_same tray, @handle.resources_table.get(rid)
    assert_same tray, @handle.tray_by_id("main")
    assert_same tray, @app.tray_by_id(Tokra::Tray::TrayIconId.new(value: "main"))
    assert_nil @handle.tray_by_id("other")
    @handle.menu_manager.global_event_listeners.each { |listener| listener.call(@handle, Tokra::Menu::MenuEvent.new(id: "a")) }
    assert_equal ["a"], heard
  end

  # tray_by_id answers only a tray the table still holds (manager/tray.rs:48-62).
  def test_tray_by_id_skips_a_rid_the_table_no_longer_holds
    tray = Tokra::Tray::TrayIconBuilder.with_id("main").build(@app)
    @handle.resources_table.take(@handle.tray_manager.tray_resource_by_id("main"))

    assert_nil @handle.tray_by_id("main")
    refute tray.native.removed?, "taking the resource is not closing it"
  end

  # remove_tray_by_id takes the resource and closes it; Tokra's close
  # takes the tray off the system tray (plan 043, decision 6).
  def test_remove_tray_by_id_closes_the_tray_and_returns_it
    tray = Tokra::Tray::TrayIconBuilder.with_id("main").build(@app)

    assert_same tray, @app.remove_tray_by_id("main")
    assert tray.native.removed?
    assert_equal [[:remove, nil, true]], tray.native.calls
    assert_nil @handle.tray_by_id("main")
    assert_nil @handle.tray_manager.tray_resource_by_id("main")
    assert_nil @handle.remove_tray_by_id("main")
  end

  def test_closing_the_trays_resource_takes_it_off_the_tray
    tray = Tokra::Tray::TrayIconBuilder.with_id("main").build(@app)

    @handle.resources_table.close(@handle.tray_manager.tray_resource_by_id("main"))

    assert tray.native.removed?
    assert_nil @handle.tray_manager.tray_resource_by_id("main")
  end

  def test_each_setter_reaches_tray_icon_on_the_main_thread
    tray = Tokra::Tray::TrayIconBuilder.new.build(@app)
    menu = Tokra::Menu::Menu.new(@handle)

    assert_nil tray.set_menu(menu)
    tray.set_menu(nil)
    tray.set_tooltip("Tip")
    tray.set_title(nil)
    tray.set_visible(false)

    assert_equal [
      [:set_menu, menu.native, true],
      [:set_menu, nil, true],
      [:set_tooltip, "Tip", true],
      [:set_title, nil, true],
      [:set_visible, false, true],
], tray.native.calls
  end

  # Tauri calls these only where tray-icon has them (tray/mod.rs:548-581).
  def test_platform_setters_reach_tray_icon_only_where_it_has_them
    tray = Tokra::Tray::TrayIconBuilder.new.build(@app)

    tray.set_temp_dir_path(Pathname("/tmp/icons"))
    tray.set_icon_as_template(true)
    tray.set_show_menu_on_left_click(false)

    expected = []
    expected << [:set_temp_dir_path, "/tmp/icons", true] if tray.native.respond_to?(:set_temp_dir_path)
    expected << [:set_icon_as_template, true, true] if tray.native.respond_to?(:set_icon_as_template)
    expected << [:set_show_menu_on_left_click, false, true] if tray.native.respond_to?(:set_show_menu_on_left_click)
    assert_equal expected, tray.native.calls
    linux = RbConfig::CONFIG["host_os"].include?("linux")
    assert_equal linux, Tokra::Native::TrayIcon.method_defined?(:set_temp_dir_path)
    assert_equal RbConfig::CONFIG["host_os"].include?("darwin"),
      Tokra::Native::TrayIcon.method_defined?(:set_icon_as_template)
    refute_equal linux, Tokra::Native::TrayIcon.method_defined?(:set_show_menu_on_left_click)
  end

  def test_rect_is_a_physical_rect_or_nil_once_removed
    tray = Tokra::Tray::TrayIconBuilder.with_id("main").build(@app)

    rect = tray.rect
    assert_equal Tokra::PhysicalPosition.new(x: 10, y: 20), rect.position
    assert_equal Tokra::PhysicalSize.new(width: 22, height: 24), rect.size
    @handle.remove_tray_by_id("main")
    assert_nil tray.rect
  end

  def test_a_call_from_another_thread_waits_for_the_main_thread
    tray = Tokra::Tray::TrayIconBuilder.new.build(@app)
    context = @handle.runtime_context
    context.attach(StubNative::Proxy.new)

    asked = Thread.new { tray.set_tooltip("Tip") }
    Thread.pass until context.instance_variable_get(:@tasks).any?
    assert_empty tray.native.calls, "the call waits for the main thread"
    context.handle_task
    assert_nil asked.value
    assert_equal [[:set_tooltip, "Tip", true]], tray.native.calls

    waiting = Thread.new do
      Thread.current.report_on_exception = false
      tray.set_title("never")
    end
    Thread.pass until context.instance_variable_get(:@tasks).any?
    context.close
    assert_raises(Tokra::Error::FailedToReceiveMessage) { waiting.value }
  end

  # A plugin recording the tray events it hears.
  class TrayEventPlugin < Tokra::Plugin
    def name = "tray-events"

    def on_event(_app, event)
      Thread.current[:heard] << [:plugin, event.event.id.to_s] if event.is_a?(Tokra::RunEvent::TrayIconEvent)
    end
  end

  def click(id)
    Tokra::Native::TrayIconEvent.new("Click", id, [10.25, 20.75], [2, -3, 22, 24], "Right", "Down")
  end

  # Tauri calls the app's listeners, then the tray's when its id matches
  # and tray_by_id finds it, then plugins and the run callback
  # (app.rs:2453-2472, 2488-2494).
  def test_a_tray_event_reaches_the_app_then_the_tray_then_the_run_callback
    StubNative.inject_event([click("main"), click("gone")])
    Thread.current[:heard] = []
    app = Tokra::Builder.default
      .on_tray_icon_event(&Ractor.shareable_proc { |handle, event| Thread.current[:heard] << [:builder, handle.class, event.id.to_s] })
      .build(native: StubNative)
    app.on_tray_icon_event { |_, event| Thread.current[:heard] << [:app, event.id.to_s] }
    app.handle.plugin(TrayEventPlugin.new(app.handle))

    app.run do |handle, event|
      case event
      when Tokra::RunEvent::Ready
        Tokra::Tray::TrayIconBuilder.with_id("main")
          .on_tray_icon_event { |tray, heard| Thread.current[:heard] << [:tray, tray.id.to_s, heard.class] }
          .build(handle)
        gone = Tokra::Tray::TrayIconBuilder.with_id("gone").build(handle)
        gone.on_tray_icon_event { |_, _| Thread.current[:heard] << [:gone] }
        handle.remove_tray_by_id("gone")
      when Tokra::RunEvent::TrayIconEvent then Thread.current[:heard] << [:run, event.event.id.to_s]
      end
    end

    assert_equal [
      [:builder, Tokra::AppHandle, "main"],
      [:app, "main"],
      [:tray, "main", Tokra::Tray::TrayIconEvent::Click],
      [:plugin, "main"],
      [:run, "main"],
      [:builder, Tokra::AppHandle, "gone"],
      [:app, "gone"],
      [:plugin, "gone"],
      [:run, "gone"],
], Thread.current[:heard]
  end

  def test_a_tray_has_one_listener_and_a_second_replaces_the_first
    StubNative.inject_event(click("main"))
    Thread.current[:heard] = []

    Tokra::Builder.default.build(native: StubNative).run do |handle, event|
      next unless event.is_a?(Tokra::RunEvent::Ready)

      tray = Tokra::Tray::TrayIconBuilder.with_id("main").on_tray_icon_event { |_, _| Thread.current[:heard] << :builder }.build(handle)
      tray.on_tray_icon_event { |_, _| Thread.current[:heard] << :second }
    end

    assert_equal [:second], Thread.current[:heard]
  end

  # Tauri's cleanup_before_exit drops every tray once the run callback has
  # heard Exit (app.rs:1303-1307; plan 043, decision 7).
  def test_the_exit_takes_every_tray_off_after_the_run_callback_hears_it
    Thread.current[:at_exit] = nil
    trays = []
    @app.run do |handle, event|
      case event
      when Tokra::RunEvent::Ready
        trays << Tokra::Tray::TrayIconBuilder.with_id("a").build(handle)
        trays << Tokra::Tray::TrayIconBuilder.with_id("b").build(handle)
        Tokra::Tray::TrayIconBuilder.with_id("taken").build(handle)
        handle.resources_table.take(handle.tray_manager.tray_resource_by_id("taken"))
      when Tokra::RunEvent::Exit then Thread.current[:at_exit] = trays.map { |tray| tray.native.removed? }
      end
    end

    assert_equal [false, false], Thread.current[:at_exit]
    assert(trays.all? { |tray| tray.native.removed? })
    assert_nil @handle.tray_by_id("a")
    assert_nil @handle.tray_manager.tray_resource_by_id("taken"),
      "cleanup_before_exit clears the icons, even one whose resource is gone (app.rs:1026-1028)"
  end

  def test_a_click_converts_as_tauris_from_and_serializes_as_tauris_test_expects
    event = Tokra::Tray::TrayIconEvent.from_native(click("id"))

    assert_equal Tokra::Tray::TrayIconEvent::Click.new(
      id: Tokra::Tray::TrayIconId.new(value: "id"),
      position: Tokra::PhysicalPosition.new(x: 10.25, y: 20.75),
      rect: Tokra::Rect.new(position: Tokra::PhysicalPosition.new(x: 2, y: -3),
        size: Tokra::PhysicalSize.new(width: 22, height: 24)),
      button: Tokra::Tray::MouseButton::Right,
      button_state: Tokra::Tray::MouseButtonState::Down
    ), event
    # tray/mod.rs:622-669, with this event's values.
    assert_equal({
      "type" => "Click",
      "button" => "Right",
      "buttonState" => "Down",
      "id" => "id",
      "position" => { "x" => 10.25, "y" => 20.75 },
      "rect" => {
"size" => { "Physical" => { "width" => 22, "height" => 24 } },
"position" => { "Physical" => { "x" => 2, "y" => -3 } },
},
    }, JSON.parse(JSON.generate(event)))
  end

  def test_the_other_events_convert_with_their_own_fields
    native = -> (kind, button = nil) { Tokra::Native::TrayIconEvent.new(kind, "t", [1.0, 2.0], [3, 4, 5, 6], button, nil) }

    double = Tokra::Tray::TrayIconEvent.from_native(native.call("DoubleClick", "Middle"))
    assert_equal Tokra::Tray::MouseButton::Middle, double.button
    assert_equal({ "type" => "DoubleClick", "button" => "Middle" }, JSON.parse(JSON.generate(double)).slice("type", "button"))
    refute JSON.parse(JSON.generate(double)).key?("buttonState")
    %w[Enter Move Leave].each do |kind|
      event = Tokra::Tray::TrayIconEvent.from_native(native.call(kind))
      assert_instance_of Tokra::Tray::TrayIconEvent.const_get(kind), event
      assert_equal %w[id position rect type], JSON.parse(JSON.generate(event)).keys.sort
    end
  end

  def test_tray_icon_ids_equal_their_text_and_serialize_as_it
    id = Tokra::Tray::TrayIconId.from(:main)

    assert_operator id, :==, "main"
    assert_equal id, Tokra::Tray::TrayIconId.from(id)
    assert_equal '"main"', JSON.generate(id)
    assert_equal "main", id.to_s
  end

  def test_mouse_buttons_and_states_are_closed_enums
    assert_equal %w[Left Right Middle], [
      Tokra::Tray::MouseButton::Left,
      Tokra::Tray::MouseButton::Right,
      Tokra::Tray::MouseButton::Middle,
].map(&:name)
    assert_equal %w[Up Down], [Tokra::Tray::MouseButtonState::Up, Tokra::Tray::MouseButtonState::Down].map(&:name)
    assert_raises(NoMethodError) { Tokra::Tray::MouseButton.new(name: "Back") }
    assert_equal '"Up"', JSON.generate(Tokra::Tray::MouseButtonState::Up)
  end

  def test_a_logical_rect_tags_its_parts_logical
    rect = Tokra::Rect.new(position: Tokra::LogicalPosition.new(x: 1.5, y: 2.5),
      size: Tokra::LogicalSize.new(width: 3.0, height: 4.0))

    assert_equal({
"position" => { "Logical" => { "x" => 1.5, "y" => 2.5 } },
"size" => { "Logical" => { "width" => 3.0, "height" => 4.0 } },
}, JSON.parse(JSON.generate(rect)))
  end

  def test_a_builder_block_must_be_shareable
    error = assert_raises(Tokra::Error) { Tokra::Builder.default.on_tray_icon_event { |_, _| nil } }
    assert_equal "on_tray_icon_event block must be Ractor-shareable (use Ractor.shareable_proc)", error.message
  end
end
