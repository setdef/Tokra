# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/stub_native"

# Tokra::Menu through a real App and AppHandle, with real muda menus and
# StubNative's window and NSApp (plan 042). StubWindowMenusNative plays a
# platform whose windows carry their own menu bars, so both of Tauri's
# branches run here.
class TestMenu < Minitest::Test
  def teardown
    StubNative.clear_event
  end

  def test_a_menu_event_reaches_app_listeners_then_the_window_listener_then_the_run_callback
    StubNative.inject_event(Tokra::Native::MenuEvent.new("save"))
    Thread.current[:heard] = []
    builder = Tokra::Builder.default
      .on_menu_event(&Ractor.shareable_proc { |handle, event| Thread.current[:heard] << [:builder, handle.class, event.id.to_s] })
    app = builder.build(native: StubNative)
    app.on_menu_event { |_handle, event| Thread.current[:heard] << [:app, event.id.to_s] }

    app.run do |handle, event|
      if event.is_a?(Tokra::RunEvent::Ready)
        handle.get_window("main").on_menu_event { |window, heard| Thread.current[:heard] << [:window, window.label, heard.id.to_s] }
      elsif event.is_a?(Tokra::RunEvent::MenuEvent)
        Thread.current[:heard] << [:run, event.event.id.to_s]
        Thread.current[:run_id] = event.event.id
      end
    end

    assert_equal [[:builder, Tokra::AppHandle, "save"], [:app, "save"], [:window, "main", "save"], [:run, "save"]],
      Thread.current[:heard]
    assert_instance_of Tokra::Menu::MenuId, Thread.current[:run_id]
  end

  def test_a_window_has_one_menu_listener_and_a_second_replaces_the_first
    StubNative.inject_event(Tokra::Native::MenuEvent.new("save"))
    Thread.current[:heard] = []

    Tokra::Builder.default.build(native: StubNative).run do |handle, event|
      next unless event.is_a?(Tokra::RunEvent::Ready)

      window = handle.get_window("main")
      window.on_menu_event { |_, _| Thread.current[:heard] << :first }
      window.on_menu_event { |_, _| Thread.current[:heard] << :second }
    end

    assert_equal [:second], Thread.current[:heard]
  end

  def test_the_builders_menu_is_the_apps_before_the_setup_hook_and_goes_on_the_new_window
    Thread.current[:setup_menu] = nil
    app = Tokra::Builder.default
      .menu(&Ractor.shareable_proc { |handle| Tokra::Menu::MenuBuilder.with_id(handle, "bar").text("open", "Open").build })
      .setup(&Ractor.shareable_proc { |a| Thread.current[:setup_menu] = a.menu&.id&.to_s })
      .build(native: StubWindowMenusNative)

    assert_nil app.menu
    app.run

    assert_equal "bar", Thread.current[:setup_menu]
    window = app.handle.get_window("main")
    assert_equal "bar", window.menu.id.to_s
    assert window.has_app_wide_menu?
    assert_equal [[:init_menu, "bar"]], window.native.menu_calls
    assert_equal ["Auto"], window.native.menu_themes, "a new window's menu takes Auto (manager/menu.rs:74-79)"
    assert_equal ["bar"], app.handle.menu_manager.menus.map { |menu| menu.id.to_s }
  end

  def test_on_macos_the_builders_menu_goes_on_nsapp_with_its_window_and_help_menus
    skip "NSApp is macOS's" unless Tokra::Native.respond_to?(:init_menu_for_nsapp)

    app = Tokra::Builder.default.build(native: StubNative)
    app.run

    menu = app.menu
    calls = StubNative.nsapp_calls
    assert_equal [:init_menu_for_nsapp, menu.id.to_s], calls.first
    assert_includes calls, [:set_windows_menu_for_nsapp, Tokra::Menu::WINDOW_SUBMENU_ID]
    assert_includes calls, [:set_help_menu_for_nsapp, Tokra::Menu::HELP_SUBMENU_ID]
    window = app.handle.get_window("main")
    assert_same menu, window.menu, "Tauri's window records the app's menu on macOS too"
    assert window.has_app_wide_menu?
  end

  def test_the_default_menu_is_macos_only_and_can_be_turned_off
    with_default = Tokra::Builder.default.build(native: StubNative).tap(&:run)
    without = Tokra::Builder.default.enable_macos_default_menu(false).build(native: StubNative).tap(&:run)

    if Tokra::Menu.os == :macos
      assert_equal %w[File Edit View Window Help], with_default.menu.items.drop(1).map(&:text)
    else
      assert_nil with_default.menu
    end
    assert_nil without.menu
  end

  def test_the_default_menu_follows_tauris_layout_for_each_platform
    handle = Tokra::Builder.default.build(native: StubNative).handle
    layouts = %i[macos windows linux].to_h do |os|
      menu = Tokra::Menu::Menu.__send__(:default_for, handle, os)
      [os, menu.items.map { |submenu| [submenu.id.to_s, submenu.text, submenu.items.map(&:text)] }]
    end

    window = [Tokra::Menu::WINDOW_SUBMENU_ID, "Window"]
    help = [Tokra::Menu::HELP_SUBMENU_ID, "Help"]
    assert_equal %w[Edit Window Help], layouts[:linux].map { |(_, text, _)| text }
    assert_equal %w[File Edit Window Help], layouts[:windows].map { |(_, text, _)| text }
    assert_equal 6, layouts[:macos].size
    assert_equal 2, layouts[:windows].first.last.size, "File: Close Window and Quit"
    assert_equal 1, layouts[:macos][1].last.size, "macOS File: Close Window only"
    assert_equal window, layouts[:linux][1].first(2)
    assert_equal 3, layouts[:linux][1].last.size
    assert_equal 4, layouts[:macos][4].last.size, "macOS's Window menu has a separator"
    assert_equal help, layouts[:windows][3].first(2)
    assert_equal 1, layouts[:windows][3].last.size, "About under Help"
    assert_empty layouts[:macos][5].last
    assert_equal 8, layouts[:macos][0].last.size
  end

  def test_set_menu_takes_windows_that_show_the_apps_menu_or_none_and_returns_the_last_menu
    app = run_app(StubWindowMenusNative)
    handle = app.handle
    window = handle.get_window("main")
    first = Tokra::Menu::Menu.with_id(handle, "first")
    second = Tokra::Menu::Menu.with_id(handle, "second")

    assert_nil handle.set_menu(first)
    assert_equal first, handle.set_menu(second)

    assert_equal "second", window.menu.id.to_s
    assert window.has_app_wide_menu?
    assert_equal [[:init_menu, "first"], [:remove_menu, "first"], [:init_menu, "second"]], window.native.menu_calls
    assert_equal ["second"], handle.menu_manager.menus.map { |menu| menu.id.to_s }
  end

  def test_set_menu_leaves_a_window_with_its_own_menu
    app = run_app(StubWindowMenusNative)
    handle = app.handle
    window = handle.get_window("main")
    own = Tokra::Menu::Menu.with_id(handle, "own")
    window.set_menu(own)

    handle.set_menu(Tokra::Menu::Menu.with_id(handle, "app"))
    handle.remove_menu

    assert_equal "own", window.menu.id.to_s
    refute window.has_app_wide_menu?
    assert_equal [[:init_menu, "own"]], window.native.menu_calls
    assert_equal [nil], window.native.menu_themes, "set_menu takes the window's own theme (window/mod.rs:1205-1214)"
    assert_equal ["own"], handle.menu_manager.menus.map { |menu| menu.id.to_s }
  end

  def test_remove_menu_takes_the_apps_menu_off_its_windows_and_out_of_the_stash
    app = run_app(StubWindowMenusNative)
    handle = app.handle
    window = handle.get_window("main")
    menu = Tokra::Menu::Menu.with_id(handle, "app")
    handle.set_menu(menu)

    assert_equal menu, handle.remove_menu

    assert_nil handle.menu
    assert_nil window.menu
    assert_equal [[:init_menu, "app"], [:remove_menu, "app"]], window.native.menu_calls
    assert_empty handle.menu_manager.menus
    assert_nil handle.remove_menu
  end

  # A menu the app gives up stays stashed while a window still shows it
  # (manager/mod.rs:689-702).
  def test_the_stash_keeps_a_menu_a_window_still_shows
    app = run_app(StubWindowMenusNative)
    handle = app.handle
    shared = Tokra::Menu::Menu.with_id(handle, "shared")
    handle.get_window("main").set_menu(shared)
    handle.menu_manager.replace_menu(shared)

    handle.menu_manager.take_menu
    handle.__send__(:remove_menu_from_stash_by_id, shared.id)

    assert_equal ["shared"], handle.menu_manager.menus.map { |menu| menu.id.to_s }
  end

  def test_hiding_and_showing_the_apps_menu_reaches_windows_that_show_it
    app = run_app(StubWindowMenusNative)
    handle = app.handle
    window = handle.get_window("main")
    assert_nil handle.hide_menu, "no app menu: nothing to hide"
    handle.set_menu(Tokra::Menu::Menu.with_id(handle, "app"))

    handle.hide_menu
    hidden = window.is_menu_visible
    handle.show_menu

    refute hidden
    assert window.is_menu_visible
    assert_equal %i[init_menu hide_menu show_menu], window.native.menu_calls.map(&:first)
  end

  def test_a_window_without_a_menu_bar_is_not_showing_one
    app = run_app(StubNative)
    window = app.handle.get_window("main")

    refute window.is_menu_visible
    assert_nil window.hide_menu
    assert_nil window.remove_menu
  end

  def test_on_macos_set_menu_waits_for_the_event_loop_to_reach_nsapp
    skip "NSApp is macOS's" unless Tokra::Native.respond_to?(:init_menu_for_nsapp)

    app = Tokra::Builder.default.enable_macos_default_menu(false).build(native: StubNative)
    menu = Tokra::Menu::Menu.with_id(app.handle, "early")
    app.set_menu(menu)
    assert_empty StubNative.nsapp_calls, "no NSApp before the loop"

    app.run
    assert_equal [[:init_menu_for_nsapp, "early"]], StubNative.nsapp_calls
    app.remove_menu
    assert_equal [:remove_menu_for_nsapp, "early"], StubNative.nsapp_calls.last
  end

  def test_a_menus_items_come_back_as_their_own_classes_with_their_ids
    handle = Tokra::Builder.default.build(native: StubNative).handle
    menu = Tokra::Menu::MenuBuilder.new(handle)
      .text("open", "Open").check("wrap", "Wrap").separator.item(Tokra::Menu::Submenu.with_id(handle, "sub", "Sub", true))
      .build

    items = menu.items

    assert_equal [Tokra::Menu::MenuItem, Tokra::Menu::CheckMenuItem, Tokra::Menu::PredefinedMenuItem, Tokra::Menu::Submenu],
      items.map(&:class)
    assert_equal "open", items.first.id.to_s
    assert items[1].is_checked, "the builder's check item starts checked, as Tauri's does"
    assert_same items[3], items[3].kind
    assert_equal items[3], menu.get("sub")
    assert_nil menu.get("missing")
    assert_equal items.first, menu.remove_at(0)
    assert_nil menu.remove_at(9)
  end

  def test_a_muda_error_is_a_menu_error_with_tauris_prefix
    handle = Tokra::Builder.default.build(native: StubNative).handle
    menu = Tokra::Menu::Menu.new(handle)

    error = assert_raises(Tokra::Error::Menu) { menu.remove(Tokra::Menu::MenuItem.new(handle, "A", true, nil)) }

    assert_equal "menu error: This menu item is not a child of this `Menu` or `Submenu`", error.message
    assert_raises(TypeError) { menu.append(menu) }
  end

  def test_item_builders_start_enabled_and_check_items_start_checked
    handle = Tokra::Builder.default.build(native: StubNative).handle

    plain = Tokra::Menu::MenuItemBuilder.with_id("save", "Save").accelerator("CmdOrCtrl+S").build(handle)
    check = Tokra::Menu::CheckMenuItemBuilder.new("Wrap").build(handle)
    off = Tokra::Menu::CheckMenuItemBuilder.new("Wrap").checked(false).enabled(false).build(handle)
    submenu = Tokra::Menu::SubmenuBuilder.with_id(handle, "edit", "Edit").enabled(false).copy_with_text("Copy It").build

    assert_equal "save", plain.id.to_s
    assert plain.is_enabled
    assert check.is_checked
    refute off.is_checked
    refute off.is_enabled
    refute submenu.is_enabled
    assert_equal ["Copy It"], submenu.items.map(&:text)
  end

  # Tauri keeps a builder item's Result and raises it from build
  # (builders/menu.rs:30-37).
  def test_a_builder_keeps_an_items_error_for_build
    app = Tokra::Builder.default.build(native: StubNative)
    context = app.handle.runtime_context
    context.attach(StubNative::Proxy.new)
    context.close
    builder = Tokra::Menu::MenuBuilder.new(app.handle)

    Thread.new { builder.text("late", "Late") }.join

    assert_raises(Tokra::Error::Runtime) { builder.build }
  end

  def test_a_call_from_another_thread_runs_on_the_main_thread_or_fails_to_receive
    app = Tokra::Builder.default.build(native: StubNative)
    handle = app.handle
    item = Tokra::Menu::MenuItem.new(handle, "Open", true, nil)
    context = handle.runtime_context
    context.attach(StubNative::Proxy.new)

    asked = Thread.new { item.text }
    Thread.pass until context.instance_variable_get(:@tasks).any?
    context.handle_task
    assert_equal "Open", asked.value

    waiting = Thread.new do
      Thread.current.report_on_exception = false
      item.text
    end
    Thread.pass until context.instance_variable_get(:@tasks).any?
    context.close
    error = assert_raises(Tokra::Error::FailedToReceiveMessage) { waiting.value }
    assert_equal "failed to receive message", error.message
  end

  def test_menu_ids_equal_their_text_and_serialize_as_it
    id = Tokra::Menu::MenuId.from(:save)

    assert_equal "save", id.value
    assert_equal id, "save"
    assert_equal Tokra::Menu::MenuId.new(value: "save"), id
    assert_same id, Tokra::Menu::MenuId.from(id)
    assert_equal '"save"', JSON.generate(id)
    assert_equal '{"id":"save"}', JSON.generate(Tokra::Menu::MenuEvent.new(id:))
  end

  def test_about_metadata_is_tauris_eleven_fields_and_its_builder_sets_each
    image = Tokra::Image.new(rgba: "\x01\x02\x03\x04".b, width: 1, height: 1)
    metadata = Tokra::Menu::AboutMetadataBuilder.new.name("Notes").version("1.0").short_version("1").authors(["Ada"])
      .comments("c").copyright("(c)").license("MIT").website("https://example.com").website_label("site")
      .credits("cr").icon(image).build

    assert_equal %i[name version short_version authors comments copyright license website website_label credits icon],
      Tokra::Menu::AboutMetadata.members
    assert_equal "Notes", metadata.name
    assert_equal ["\x01\x02\x03\x04".b, 1, 1], metadata.to_native[:icon]
    assert_nil Tokra::Menu::AboutMetadata.new.name
    handle = Tokra::Builder.default.build(native: StubNative).handle
    assert_kind_of Tokra::Menu::PredefinedMenuItem, Tokra::Menu::PredefinedMenuItem.about(handle, nil, metadata)
  end

  # Tauri's query goes unanswered and answers false (window/mod.rs:1334-1363).
  def test_a_menu_visibility_query_the_main_thread_never_answers_is_false
    app = Tokra::Builder.default.build(native: StubWindowMenusNative)
    handle = app.handle
    window = Tokra::Window.new(label: "main", native: StubWindowMenusNative::Window.new(nil), app_handle: handle)
    window.set_menu(Tokra::Menu::Menu.with_id(handle, "bar"))
    assert window.is_menu_visible, "the main thread answers at once"
    context = handle.runtime_context
    context.attach(StubNative::Proxy.new)

    waiting = Thread.new { window.is_menu_visible }
    Thread.pass until context.instance_variable_get(:@tasks).any?
    context.close

    refute waiting.value
  end

  # Tauri's message hook translates the stashed menus' accelerators
  # (app.rs:2145-2162), so the event loop's list follows the stash.
  def test_the_windows_accelerator_list_follows_the_stash
    app = Tokra::Builder.default.build(native: AcceleratorNative)
    handle = app.handle
    AcceleratorNative.lists.clear

    handle.set_menu(Tokra::Menu::Menu.with_id(handle, "first"))
    handle.set_menu(Tokra::Menu::Menu.with_id(handle, "second"))
    handle.remove_menu

    assert_equal [["first"], [], ["second"], []], AcceleratorNative.lists
  end

  # StubWindowMenusNative with Windows' accelerator list.
  module AcceleratorNative
    StubWindowMenusNative.constants.each { |name| const_set(name, StubWindowMenusNative.const_get(name)) }

    def self.lists
      @lists ||= []
    end

    def self.set_accelerator_menus(menus)
      lists << menus.map(&:id)
      nil
    end
  end

  private def run_app(native)
    Tokra::Builder.default.enable_macos_default_menu(false).build(native:).tap(&:run)
  end
end
