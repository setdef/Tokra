# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/stub_native"

# The plugin:menu commands, routed through the app's own plugin store with
# real muda menus, as the JavaScript API sends them (menu/plugin.rs).
class TestMenuPlugin < Minitest::Test
  def setup
    @app = Tokra::Builder.default.build(native: StubWindowMenusNative)
    @handle = @app.handle
    @window = Tokra::Window.new(label: "main", native: StubWindowMenusNative::Window.new(nil), app_handle: @handle)
    @handle.windows["main"] = @window
    @native_webview = StubNative::WebView.new
    @webview = Tokra::Webview.new(label: "main", native: @native_webview, window: @window, app_handle: @handle)
    @table = @webview.resources_table
  end

  def teardown
    StubNative.clear_event
  end

  def test_new_builds_a_menu_from_nested_payloads_and_existing_items
    _, (open_rid,) = call("new", "kind" => "MenuItem", "options" => { "id" => "open", "text" => "Open" })
    ok, (rid, id) = call("new", "kind" => "Menu", "options" => {
      "id" => "bar",
      "items" => [
        {
"id" => "file",
"text" => "File",
"items" => [
  [open_rid, "MenuItem"],
  { "item" => "Separator" },
  { "id" => "wrap", "text" => "Wrap", "checked" => false },
  { "item" => { "About" => { "name" => "Notes", "websiteLabel" => "site" } } },
        ],
},
        { "text" => "Help" },
      ],
    })

    assert ok, rid
    assert_equal "bar", id
    menu = @table.get(rid)
    file, help = menu.items
    assert_instance_of Tokra::Menu::Submenu, file
    assert_instance_of Tokra::Menu::MenuItem, help, "a payload with no items is a MenuItem"
    assert_equal [Tokra::Menu::MenuItem, Tokra::Menu::PredefinedMenuItem, Tokra::Menu::CheckMenuItem, Tokra::Menu::PredefinedMenuItem],
      file.items.map(&:class)
    assert_equal "open", file.items.first.id.to_s
    refute file.items[2].is_checked
  end

  # serde's untagged enum takes the first variant that reads: a submenu
  # whose items do not read is still a MenuItem (plugin.rs:310-320).
  def test_an_untagged_payload_falls_through_to_the_first_variant_that_reads
    _, (rid,) = call("new", "kind" => "Menu", "options" => {
      "items" => [{ "text" => "File", "items" => [{ "bogus" => true }] }],
    })

    assert_instance_of Tokra::Menu::MenuItem, @table.get(rid).items.first
  end

  def test_payloads_that_read_as_nothing_reject_in_serdes_words
    assert_rejects "invalid args `options` for command `new`: data did not match any variant of untagged enum MenuItemPayloadKind",
      "new", "kind" => "Menu", "options" => { "items" => [5] }
    assert_rejects "invalid args `kind` for command `new`: unknown variant `Bogus`, expected one of `Menu`, `MenuItem`, `Predefined`, `Submenu`, `Check`, `Icon`",
      "new", "kind" => "Bogus"
    assert_rejects "invalid args `kind` for command `new`: invalid type: integer `1`, expected string or map",
      "new", "kind" => 1
    assert_rejects "invalid args `options` for command `new`: invalid type: unit variant, expected newtype variant",
      "new", "kind" => "Predefined", "options" => { "item" => "About" }
    assert_rejects "invalid args `options` for command `new`: invalid type: integer `5`, expected a string",
      "new", "kind" => "MenuItem", "options" => { "text" => 5 }
    assert_rejects "invalid args `handler` for command `new`: command new missing required key handler",
      "new", { "kind" => "MenuItem" }, false
  end

  # Tauri panics in these two places; Tokra rejects with the panic's text
  # (plan 042, decision 8).
  def test_what_tauri_panics_on_rejects_with_the_panics_text
    _, (menu_rid,) = call("new", "kind" => "Menu")
    _, (item_rid,) = call("new", "kind" => "Predefined", "options" => { "item" => "Copy" })

    assert_rejects "called `Option::unwrap()` on a `None` value", "new", "kind" => "Predefined"
    assert_rejects "internal error: entered unreachable code", "text", "rid" => menu_rid, "kind" => "Menu"
    assert_rejects "internal error: entered unreachable code", "is_enabled", "rid" => item_rid, "kind" => "Predefined"
    assert_rejects "internal error: entered unreachable code",
      "set_accelerator", "rid" => item_rid, "kind" => "Predefined", "accelerator" => nil
  end

  def test_a_wrong_kind_or_rid_rejects_as_tauri_does
    _, (menu_rid,) = call("new", "kind" => "Menu")
    _, (item_rid,) = call("new", "kind" => "MenuItem", "options" => { "text" => "A" })

    assert_rejects "unexpected menu item kind", "append", "rid" => item_rid, "kind" => "MenuItem", "items" => []
    assert_rejects "The resource id #{menu_rid} is invalid.", "text", "rid" => menu_rid, "kind" => "MenuItem"
    assert_rejects "The resource id #{item_rid} is invalid.", "is_checked", "rid" => item_rid
    assert_rejects "insertion index (is 4) should be <= len (is 0)",
      "insert", "rid" => menu_rid, "kind" => "Menu", "items" => [[item_rid, "MenuItem"]], "position" => 4
  end

  def test_items_get_and_remove_at_answer_rid_id_and_kind
    _, (menu_rid,) = call("new", "kind" => "Menu", "options" => {
      "items" => [
        { "id" => "a", "text" => "A" },
        { "id" => "b", "text" => "B", "checked" => true },
        { "id" => "s", "text" => "S", "items" => [] },
],
    })

    _, listed = call("items", "rid" => menu_rid, "kind" => "Menu")
    _, found = call("get", "rid" => menu_rid, "kind" => "Menu", "id" => "b")
    _, missing = call("get", "rid" => menu_rid, "kind" => "Menu", "id" => "z")
    _, removed = call("remove_at", "rid" => menu_rid, "kind" => "Menu", "position" => 0)
    _, none = call("remove_at", "rid" => menu_rid, "kind" => "Menu", "position" => 9)

    assert_equal [%w[a MenuItem], %w[b Check], %w[s Submenu]], listed.map { |(_, id, kind)| [id, kind] }
    assert_equal %w[b Check], found.drop(1)
    assert_instance_of Tokra::Menu::CheckMenuItem, @table.get(found.first)
    assert_nil missing
    assert_equal %w[a MenuItem], removed.drop(1)
    assert_nil none
    assert_equal 2, @table.get(menu_rid).items.size
  end

  def test_append_prepend_insert_and_remove_change_the_menu
    _, (menu_rid,) = call("new", "kind" => "Submenu", "options" => { "id" => "s", "text" => "S" })
    _, (item_rid,) = call("new", "kind" => "MenuItem", "options" => { "id" => "x", "text" => "X" })

    call("append", "rid" => menu_rid, "kind" => "Submenu", "items" => [{ "id" => "end", "text" => "End" }])
    call("prepend", "rid" => menu_rid, "kind" => "Submenu", "items" => [[item_rid, "MenuItem"]])
    call("insert", "rid" => menu_rid, "kind" => "Submenu", "position" => 1,
      "items" => [{ "id" => "i1", "text" => "1" }, { "id" => "i2", "text" => "2" }])
    ids = @table.get(menu_rid).items.map { |item| item.id.to_s }
    ok, = call("remove", "rid" => menu_rid, "kind" => "Submenu", "item" => [item_rid, "MenuItem"])
    again, message = call("remove", "rid" => menu_rid, "kind" => "Submenu", "item" => [item_rid, "MenuItem"])

    assert_equal %w[x i1 i2 end], ids
    assert ok
    refute again
    assert_equal "menu error: This menu item is not a child of this `Menu` or `Submenu`", message
  end

  def test_item_state_commands_read_and_write_the_item
    _, (rid,) = call("new", "kind" => "Check", "options" => { "text" => "Wrap", "checked" => true })

    call("set_text", "rid" => rid, "kind" => "Check", "text" => "Word Wrap")
    call("set_enabled", "rid" => rid, "kind" => "Check", "enabled" => false)
    call("set_checked", "rid" => rid, "checked" => false)
    ok, = call("set_accelerator", "rid" => rid, "kind" => "Check", "accelerator" => "CmdOrCtrl+W")

    assert ok
    assert_equal [true, "Word Wrap"], call("text", "rid" => rid, "kind" => "Check")
    assert_equal [true, false], call("is_enabled", "rid" => rid, "kind" => "Check")
    assert_equal [true, false], call("is_checked", "rid" => rid)
  end

  def test_create_default_and_set_as_app_menu_answer_the_replaced_menu
    _, (default_rid, default_id) = call("create_default")
    _, (other_rid,) = call("new", "kind" => "Menu", "options" => { "id" => "other" })

    first = call("set_as_app_menu", "rid" => default_rid)
    second = call("set_as_app_menu", "rid" => other_rid)

    assert_equal [true, nil], first
    assert_equal default_id, second.last.last
    assert_equal default_id, @table.get(second.last.first).id.to_s
    assert_equal "other", @handle.menu.id.to_s
    assert @table.get(default_rid).get(Tokra::Menu::WINDOW_SUBMENU_ID)
  end

  def test_set_as_window_menu_takes_the_named_window_or_the_callers
    _, (rid,) = call("new", "kind" => "Menu", "options" => { "id" => "win" })

    assert_equal [true, nil], call("set_as_window_menu", "rid" => rid, "window" => "nowhere")
    assert_nil @window.menu, "no window has that label, so nothing changed"
    assert_equal [true, nil], call("set_as_window_menu", "rid" => rid, "window" => nil)
    assert_equal "win", @window.menu.id.to_s
    assert_equal [[:init_menu, "win"]], @window.native.menu_calls
  end

  def test_an_items_channels_hear_its_clicks_after_the_app_listeners
    _, (rid, id) = call("new", { "kind" => "MenuItem", "options" => { "id" => "go", "text" => "Go" } },
      "__CHANNEL__:41")
    call("append", "rid" => call("new", "kind" => "Menu").last.first, "kind" => "Menu",
      "items" => [{ "id" => "act", "text" => "Act", "handler" => "__CHANNEL__:42" }])
    plugin = @handle.__send__(:manager).plugins.instance_variable_get(:@store).find { |p| p.name == "menu" }

    plugin.on_event(@handle, Tokra::RunEvent::MenuEvent.new(event: Tokra::Menu::MenuEvent.new(id: Tokra::Menu::MenuId.new(value: "go"))))
    plugin.on_event(@handle, Tokra::RunEvent::MenuEvent.new(event: Tokra::Menu::MenuEvent.new(id: Tokra::Menu::MenuId.new(value: "act"))))
    plugin.on_event(@handle, Tokra::RunEvent::MenuEvent.new(event: Tokra::Menu::MenuEvent.new(id: Tokra::Menu::MenuId.new(value: "nobody"))))

    assert_kind_of Integer, rid
    assert_equal "go", id
    assert_equal 2, @native_webview.evals.size
    assert_match(/41.*"go"/m, @native_webview.evals[0])
    assert_match(/42.*"act"/m, @native_webview.evals[1])
  end

  # Tauri's set_as_windows_menu_for_nsapp command calls
  # set_as_help_menu_for_nsapp, as written (plugin.rs:805-838).
  def test_both_nsapp_commands_make_the_submenu_nsapps_help_menu
    skip "NSApp is macOS's" unless Tokra::Native.respond_to?(:init_menu_for_nsapp)

    @app = Tokra::Builder.default.build(native: StubNative)
    @handle = @app.handle
    @webview = Tokra::Webview.new(label: "main", native: StubNative::WebView.new, window: @window, app_handle: @handle)
    _, (rid, id) = call("new", "kind" => "Submenu", "options" => { "text" => "Window" })

    call("set_as_windows_menu_for_nsapp", "rid" => rid)
    call("set_as_help_menu_for_nsapp", "rid" => rid)

    assert_equal [[:set_help_menu_for_nsapp, id], [:set_help_menu_for_nsapp, id]], StubNative.nsapp_calls
  end

  # An icon payload's icon is a NativeIcon name or a JsImage, the untagged
  # Icon enum (plugin.rs:175-191); +new+ for an Icon with no icon shows
  # NativeIcon::User (plugin.rs:443-449).
  def test_new_makes_icon_items_and_submenus_with_icons
    image = { "rgba" => [255] * 16, "width" => 2, "height" => 2 }
    ok, (rid, id) = call("new", "kind" => "Icon", "options" => {
      "id" => "lock", "text" => "Lock", "icon" => "LockLocked", "enabled" => false, "accelerator" => "CmdOrCtrl+L"
    })
    assert ok, rid
    item = @table.get(rid)
    assert_instance_of Tokra::Menu::IconMenuItem, item
    assert_equal ["lock", "Lock", false], [id, item.text, item.is_enabled]
    ok, (plain_rid,) = call("new", "kind" => "Icon", "options" => { "text" => "Plain" })
    assert ok, plain_rid
    assert_instance_of Tokra::Menu::IconMenuItem, @table.get(plain_rid)

    ok, (submenu_rid,) = call("new", "kind" => "Submenu", "options" => {
      "id" => "tools",
      "text" => "Tools",
      "icon" => image,
      "items" => [
        { "id" => "share", "text" => "Share", "icon" => "Share" },
        { "id" => "paint", "text" => "Paint", "icon" => image },
        [plain_rid, "Icon"],
        { "id" => "off", "text" => "Off", "icon" => "Add", "enabled" => false, "accelerator" => "CmdOrCtrl+O" },
      ],
    })
    assert ok, submenu_rid
    tools = @table.get(submenu_rid)
    assert_instance_of Tokra::Menu::Submenu, tools
    assert_equal [Tokra::Menu::IconMenuItem] * 4, tools.items.map(&:class)
    _, listed = call("items", "rid" => submenu_rid, "kind" => "Submenu")
    assert_equal [%w[share Icon], %w[paint Icon], [@table.get(plain_rid).id.to_s, "Icon"], %w[off Icon]],
      listed.map { |(_, item_id, kind)| [item_id, kind] }
    refute tools.get("off").is_enabled, "a nested icon payload's enabled reaches the item (plugin.rs:204-209)"
    # muda answers no item's accelerator, so the payload shows where it goes.
    plugin = @handle.__send__(:manager).plugins.instance_variable_get(:@store).find { |p| p.name == "menu" }
    payload = plugin.__send__(:payload_kind, { "text" => "Off", "icon" => "Add", "enabled" => false, "accelerator" => "CmdOrCtrl+O" })
    assert_equal [false, "CmdOrCtrl+O", Tokra::Menu::NativeIcon::Add], [payload.enabled, payload.accelerator, payload.icon]
    ok, (native_rid,) = call("new", "kind" => "Submenu", "options" => { "id" => "s", "text" => "S", "icon" => "Folder" })
    assert ok, native_rid
    assert_equal "s", @table.get(native_rid).id.to_s
  end

  # serde takes the first variant of MenuItemPayloadKind that reads, and
  # IconMenuItemPayload comes before SubmenuPayload and ignores +items+
  # (plugin.rs:310-320): a nested submenu with an icon is an icon item, in
  # Tauri as here.
  def test_a_nested_submenu_payload_with_an_icon_reads_as_an_icon_item
    ok, (rid,) = call("new", "kind" => "Menu", "options" => {
"items" => [
      { "id" => "tools", "text" => "Tools", "icon" => "Folder", "items" => [{ "text" => "Run" }] },
    ],
})

    assert ok, rid
    assert_equal [Tokra::Menu::IconMenuItem], @table.get(rid).items.map(&:class)
  end

  def test_an_icon_items_channels_hear_its_clicks
    call("new", { "kind" => "Icon", "options" => { "id" => "lock", "text" => "Lock" } }, "__CHANNEL__:51")
    call("append", "rid" => call("new", "kind" => "Menu").last.first, "kind" => "Menu",
      "items" => [{ "id" => "share", "text" => "Share", "icon" => "Share", "handler" => "__CHANNEL__:52" }])
    plugin = @handle.__send__(:manager).plugins.instance_variable_get(:@store).find { |p| p.name == "menu" }

    %w[lock share].each do |id|
      plugin.on_event(@handle, Tokra::RunEvent::MenuEvent.new(event: Tokra::Menu::MenuEvent.new(id: Tokra::Menu::MenuId.new(value: id))))
    end

    assert_equal 2, @native_webview.evals.size
    assert_match(/51.*"lock"/m, @native_webview.evals[0])
    assert_match(/52.*"share"/m, @native_webview.evals[1])
  end

  def test_the_items_commands_answer_for_an_icon_item
    _, (rid,) = call("new", "kind" => "Icon", "options" => { "text" => "Lock", "icon" => "LockLocked" })
    item = { "rid" => rid, "kind" => "Icon" }

    assert_equal [true, "Lock"], call("text", item)
    call("set_text", item.merge("text" => "Unlock"))
    call("set_enabled", item.merge("enabled" => false))
    assert_equal [true, false], call("is_enabled", item)
    assert_equal [true, nil], call("set_accelerator", item.merge("accelerator" => "CmdOrCtrl+U"))
    assert_equal "Unlock", @table.get(rid).text
  end

  # set_icon takes a NativeIcon, an image, or null on an Icon or a Submenu
  # (plugin.rs:858-882), and reaches unreachable!() for any other kind.
  def test_set_icon_changes_the_icon_of_an_icon_item_or_a_submenu
    _, (icon_rid,) = call("new", "kind" => "Icon", "options" => { "text" => "I" })
    _, (submenu_rid,) = call("new", "kind" => "Submenu", "options" => { "text" => "S" })
    _, (item_rid,) = call("new", "kind" => "MenuItem", "options" => { "text" => "M" })
    image_rid = @table.add(Tokra::Image.new(rgba: "\xFF".b * 4, width: 1, height: 1))

    [[icon_rid, "Icon"], [submenu_rid, "Submenu"]].each do |rid, kind|
      ["Add", { "rgba" => [0] * 4, "width" => 1, "height" => 1 }, image_rid, nil].each do |icon|
        assert_equal [true, nil], call("set_icon", "rid" => rid, "kind" => kind, "icon" => icon), [kind, icon].inspect
      end
    end
    assert_rejects Tokra::Menu::Plugin::UNREACHABLE, "set_icon", "rid" => item_rid, "kind" => "MenuItem", "icon" => "Add"
    assert_rejects "The resource id #{item_rid} is invalid.", "set_icon", "rid" => item_rid, "kind" => "Icon", "icon" => nil
  end

  def test_an_icon_muda_refuses_or_that_reads_as_nothing_rejects
    short = { "rgba" => [255] * 4, "width" => 2, "height" => 2 }
    text = "The specified dimensions (2x2) don't match the number of pixels supplied by the `rgba` argument (1). " \
      "For those dimensions, the expected pixel count is 4."
    _, (rid,) = call("new", "kind" => "Icon", "options" => { "text" => "I" })

    assert_rejects text, "new", "kind" => "Icon", "options" => { "text" => "I", "icon" => short }
    assert_rejects text, "new", "kind" => "Submenu", "options" => { "text" => "S", "icon" => short }
    assert_rejects text, "set_icon", "rid" => rid, "kind" => "Icon", "icon" => short
    assert_rejects "invalid args `icon` for command `set_icon`: data did not match any variant of untagged enum Icon",
      "set_icon", "rid" => rid, "kind" => "Icon", "icon" => true
  end

  # Sends +command+ through the app's plugin store and answers
  # <tt>[resolved?, value]</tt>.
  private def call(command, payload = {}, handler = "__CHANNEL__:1")
    payload = payload.merge("handler" => handler) if command == "new" && handler
    answer = nil
    invoke = Tokra::Ipc::Invoke.new(command:, payload:, webview: @webview,
      responder: -> (success, value) { answer = [success, JSON.parse(value)] })
    @handle.__send__(:manager).plugins.extend_api("menu", invoke)
    answer
  end

  private def assert_rejects(message, command, payload, handler = "__CHANNEL__:1")
    assert_equal [false, message], call(command, payload, handler)
  end
end
