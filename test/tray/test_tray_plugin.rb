# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/stub_native"

# The plugin:tray commands, routed through the app's own plugin store with
# real muda menus and StubNative's tray, as the JavaScript API sends them
# (tray/plugin.rs, packages/api/src/tray.ts).
class TestTrayPlugin < Minitest::Test
  def setup
    @app = Tokra::Builder.default.build(native: StubNative)
    @handle = @app.handle
    @window = Tokra::Window.new(label: "main", native: StubNative::Window.new(nil), app_handle: @handle)
    @handle.windows["main"] = @window
    @native_webview = StubNative::WebView.new
    @webview = Tokra::Webview.new(label: "main", native: @native_webview, window: @window, app_handle: @handle)
    @table = @webview.resources_table
  end

  def teardown
    StubNative.clear_event
  end

  def rgba
    { "rgba" => [32, 128, 224, 255] * 4, "width" => 2, "height" => 2 }
  end

  # TrayIcon.new sends its options with the menu as [rid, kind] and the
  # icon transformed (tray.ts:192-212); the tray goes in the app's table.
  def test_new_builds_a_tray_from_the_pages_options_and_answers_its_rid_and_id
    menu = Tokra::Menu::Menu.with_id(@handle, "tray-menu")
    menu_rid = @table.add(menu)
    ok, (rid, id) = call("new", "options" => {
      "id" => "main",
      "menu" => [menu_rid, "Menu"],
      "icon" => rgba,
      "tooltip" => "Tip",
      "title" => "Title",
      "tempDirPath" => "/tmp/icons",
      "iconAsTemplate" => true,
      "showMenuOnLeftClick" => false,
    })

    assert ok, rid
    assert_equal "main", id
    tray = @handle.resources_table.get(rid)
    assert_instance_of Tokra::Tray::TrayIcon, tray
    refute @table.has?(rid), "the tray is the app's, not the webview's"
    attributes = tray.native.attributes
    assert_same menu.native, attributes["menu"]
    assert_instance_of Tokra::Native::TrayIcon::Icon, attributes["icon"]
    assert_equal ["Tip", "Title", "/tmp/icons", true, false],
      attributes.values_at("tooltip", "title", "temp_dir_path", "icon_is_template", "menu_on_left_click")
  end

  def test_new_with_empty_options_takes_tray_icons_next_id
    _, (rid, id) = call("new", "options" => {})

    assert_match(/\A\d+\z/, id)
    assert_same @handle.tray_by_id(id), @handle.resources_table.get(rid)
  end

  # The deprecated menuOnLeftClick, then showMenuOnLeftClick, which wins
  # (plugin.rs:83-89).
  def test_show_menu_on_left_click_is_read_after_the_deprecated_menu_on_left_click
    call("new", "options" => { "menuOnLeftClick" => false })
    assert_equal false, StubNative::TrayIcon.instances.last.attributes["menu_on_left_click"]

    call("new", "options" => { "menuOnLeftClick" => false, "showMenuOnLeftClick" => true })
    assert_equal true, StubNative::TrayIcon.instances.last.attributes["menu_on_left_click"]
  end

  def test_new_reads_its_options_from_a_sequence_of_nine_as_serde_does
    ok, (_, id) = call("new", "options" => ["seq", nil, nil, "Tip", nil, nil, nil, nil, nil])

    assert ok
    assert_equal "seq", id
    assert_equal "Tip", StubNative::TrayIcon.instances.last.attributes["tooltip"]
    assert_rejects "invalid args `options` for command `new`: invalid length 2, expected struct TrayIconOptions with 9 elements",
      "new", "options" => ["a", nil]
    assert_rejects "invalid args `options` for command `new`: invalid length 10, expected fewer elements in array",
      "new", "options" => Array.new(10)
  end

  def test_new_rejects_options_in_serdes_words
    assert_rejects "invalid args `options` for command `new`: invalid type: integer `5`, expected struct TrayIconOptions",
      "new", "options" => 5
    assert_rejects "invalid args `options` for command `new`: invalid type: integer `5`, expected a string",
      "new", "options" => { "tooltip" => 5 }
    assert_rejects "invalid args `options` for command `new`: invalid type: integer `1`, expected path string",
      "new", "options" => { "tempDirPath" => 1 }
    assert_rejects "invalid args `options` for command `new`: invalid type: string \"yes\", expected a boolean",
      "new", "options" => { "iconAsTemplate" => "yes" }
    assert_rejects "invalid args `options` for command `new`: invalid length 1, expected a tuple of size 2",
      "new", "options" => { "menu" => [1] }
    assert_rejects "invalid args `options` for command `new`: unknown variant `Tray`, expected one of `Menu`, " \
      "`MenuItem`, `Predefined`, `Submenu`, `Check`, `Icon`", "new", "options" => { "menu" => [1, "Tray"] }
    assert_rejects "invalid args `options` for command `new`: command new missing required key options", "new", {}
  end

  # Only a Menu or a Submenu, and Tauri names the kind before it looks the
  # rid up (plugin.rs:55-67).
  def test_new_takes_a_menu_or_submenu_and_rejects_other_kinds_before_the_lookup
    submenu = Tokra::Menu::Submenu.new(@handle, "More", true)
    ok, (rid,) = call("new", "options" => { "menu" => [@table.add(submenu), "Submenu"] })
    assert ok
    assert_same submenu.native, @handle.resources_table.get(rid).native.attributes["menu"]

    assert_rejects "unexpected menu item kind", "new", "options" => { "menu" => [999, "Check"] }
    assert_rejects "The resource id 999 is invalid.", "new", "options" => { "menu" => [999, "Menu"] }
    submenu_rid = @table.add(submenu)
    assert_rejects "The resource id #{submenu_rid} is invalid.", "new", "options" => { "menu" => [submenu_rid, "Menu"] }
  end

  def test_a_trays_channel_hears_its_events_as_tauris_json
    _, (_, id) = call("new", { "options" => { "id" => "main" } }, "__CHANNEL__:61")
    call("new", { "options" => { "id" => "other" } }, "__CHANNEL__:62")

    @app.__send__(:dispatch_tray_icon_event,
      Tokra::Native::TrayIconEvent.new("Click", id, [1.5, 2.5], [3, 4, 5, 6], "Left", "Up"), nil)

    assert_equal 1, @native_webview.evals.size
    assert_match(/61/, @native_webview.evals[0])
    assert_includes @native_webview.evals[0],
      '{"type":"Click","id":"main","position":{"x":1.5,"y":2.5},"rect":{"position":{"Physical":{"x":3,"y":4}},' \
        '"size":{"Physical":{"width":5,"height":6}}},"button":"Left","buttonState":"Up"}'
  end

  def test_get_by_id_answers_the_trays_rid_or_null
    _, (rid,) = call("new", "options" => { "id" => "main" })

    assert_equal [true, rid], call("get_by_id", "id" => "main")
    assert_equal [true, nil], call("get_by_id", "id" => "nobody")
    assert_rejects "invalid args `id` for command `get_by_id`: invalid type: integer `1`, expected a borrowed string",
      "get_by_id", "id" => 1
    assert_rejects "invalid args `id` for command `remove_by_id`: invalid type: null, expected a borrowed string",
      "remove_by_id", "id" => nil
  end

  def test_remove_by_id_takes_the_tray_off_or_rejects_an_unknown_id
    _, (rid,) = call("new", "options" => { "id" => "main" })
    tray = @handle.resources_table.get(rid)

    assert_equal [true, nil], call("remove_by_id", "id" => "main")
    assert tray.native.removed?
    assert_rejects "Can't find a tray associated with this id: main", "remove_by_id", "id" => "main"
  end

  # The page's TrayIcon#close reaches plugin:resources|close, which falls
  # back to the app's table (resources/plugin.rs:13-22).
  def test_the_pages_close_takes_the_tray_off_through_the_resources_plugin
    _, (rid,) = call("new", "options" => { "id" => "main" })
    tray = @handle.resources_table.get(rid)

    assert_equal [true, nil], call("close", { "rid" => rid }, nil, "resources")
    assert tray.native.removed?
    assert_nil @handle.tray_by_id("main")
  end

  def test_set_icon_takes_an_image_from_the_webviews_table_or_null
    _, (rid,) = call("new", "options" => {})
    tray = @handle.resources_table.get(rid)
    image_rid = @table.add(Tokra::Image.new(rgba: "\x01\x02\x03\x04".b, width: 1, height: 1))

    assert_equal [true, nil], call("set_icon", "rid" => rid, "icon" => image_rid)
    assert_equal [true, nil], call("set_icon", "rid" => rid, "icon" => nil)
    assert_equal [Tokra::Native::TrayIcon::Icon, NilClass], tray.native.calls.map { |(_, icon)| icon.class }
    assert_rejects "The specified dimensions (2x2) don't match the number of pixels supplied by the `rgba` argument " \
      "(1). For those dimensions, the expected pixel count is 4.", "set_icon",
      "rid" => rid, "icon" => { "rgba" => [1, 2, 3, 4], "width" => 2, "height" => 2 }
  end

  # Tauri reads every argument before it looks the tray up
  # (plugin.rs:110-125).
  def test_set_icon_reads_the_icon_before_it_looks_the_tray_up
    assert_rejects "invalid args `icon` for command `set_icon`: data did not match any variant of untagged enum JsImage",
      "set_icon", "rid" => 999, "icon" => true
    assert_rejects "The resource id 999 is invalid.", "set_icon", "rid" => 999, "icon" => nil
  end

  def test_set_menu_takes_a_menu_or_submenu_or_null
    _, (rid,) = call("new", "options" => {})
    tray = @handle.resources_table.get(rid)
    menu = Tokra::Menu::Menu.new(@handle)

    assert_equal [true, nil], call("set_menu", "rid" => rid, "menu" => [@table.add(menu), "Menu"])
    assert_equal [true, nil], call("set_menu", "rid" => rid, "menu" => nil)
    assert_equal [[:set_menu, menu.native, true], [:set_menu, nil, true]], tray.native.calls
    assert_rejects "unexpected menu item kind", "set_menu", "rid" => rid, "menu" => [1, "MenuItem"]
  end

  def test_the_text_and_flag_commands_reach_the_tray
    _, (rid,) = call("new", "options" => {})
    tray = @handle.resources_table.get(rid)

    call("set_tooltip", "rid" => rid, "tooltip" => "Tip")
    call("set_title", "rid" => rid, "title" => nil)
    call("set_visible", "rid" => rid, "visible" => false)
    call("set_temp_dir_path", "rid" => rid, "path" => "/tmp/icons")
    call("set_icon_as_template", "rid" => rid, "asTemplate" => true)
    call("set_show_menu_on_left_click", "rid" => rid, "onLeft" => false)

    expected = [[:set_tooltip, "Tip", true], [:set_title, nil, true], [:set_visible, false, true]]
    expected << [:set_temp_dir_path, "/tmp/icons", true] if tray.native.respond_to?(:set_temp_dir_path)
    expected << [:set_icon_as_template, true, true] if tray.native.respond_to?(:set_icon_as_template)
    expected << [:set_show_menu_on_left_click, false, true] if tray.native.respond_to?(:set_show_menu_on_left_click)
    assert_equal expected, tray.native.calls
  end

  def test_the_commands_reject_bad_arguments_and_a_rid_that_is_no_tray
    menu_rid = @handle.resources_table.add(Tokra::Menu::Menu.new(@handle))

    assert_rejects "invalid args `visible` for command `set_visible`: invalid type: null, expected a boolean",
      "set_visible", "rid" => 1, "visible" => nil
    assert_rejects "invalid args `visible` for command `set_visible`: command set_visible missing required key visible",
      "set_visible", "rid" => 1
    assert_rejects "invalid args `path` for command `set_temp_dir_path`: invalid type: integer `1`, expected path string",
      "set_temp_dir_path", "rid" => 1, "path" => 1
    assert_rejects "invalid args `rid` for command `set_title`: invalid value: integer `-1`, expected u32",
      "set_title", "rid" => -1, "title" => nil
    assert_rejects "The resource id #{menu_rid} is invalid.", "set_tooltip", "rid" => menu_rid, "tooltip" => nil
  end

  def test_an_unknown_command_is_not_the_plugins
    invoke = Tokra::Ipc::Invoke.new(command: "rect", payload: {}, webview: @webview, responder: -> (*) {})

    refute @handle.__send__(:manager).plugins.extend_api("tray", invoke)
  end

  private def call(command, payload = {}, handler = "__CHANNEL__:1", plugin = "tray")
    payload = payload.merge("handler" => handler) if command == "new" && handler
    answer = nil
    invoke = Tokra::Ipc::Invoke.new(command:, payload:, webview: @webview,
      responder: -> (success, value) { answer = [success, JSON.parse(value)] })
    @handle.__send__(:manager).plugins.extend_api(plugin, invoke)
    answer
  end

  private def assert_rejects(message, command, payload, handler = "__CHANNEL__:1")
    assert_equal [false, message], call(command, payload, handler)
  end
end
