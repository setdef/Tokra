# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/stub_native"

# Context menus and the Windows menu theme through a real App, AppHandle,
# and Window, with real muda menus and StubNative's window, which records
# each popup instead of tracking the pointer (plan 042, phase 3).
class TestContextMenu < Minitest::Test
  def setup
    @app = Tokra::Builder.default.build(native: StubWindowsMenusNative)
    @handle = @app.handle
    @window = Tokra::Window.new(label: "main", native: StubWindowsMenusNative::Window.new(nil), app_handle: @handle)
  end

  def teardown
    StubNative.clear_event
  end

  # Tauri's popup shows at the pointer and popup_at at a position, each
  # on the main thread (menu/menu.rs:29-80, menu/submenu.rs:22-73).
  def test_a_menu_and_a_submenu_pop_up_at_the_pointer_or_at_a_position
    menu = Tokra::Menu::Menu.with_id(@handle, "context")
    submenu = Tokra::Menu::Submenu.with_id(@handle, "nested", "Nested", true)

    assert_nil menu.popup(@window)
    assert_nil menu.popup_at(@window, Tokra::LogicalPosition.new(x: 40, y: 60.5))
    assert_nil submenu.popup(@window)
    assert_nil submenu.popup_at(@window, Tokra::PhysicalPosition.new(x: 3, y: 4))

    assert_equal [
      ["context", nil, true],
      ["context", [false, 40.0, 60.5], true],
      ["nested", nil, true],
      ["nested", [true, 3.0, 4.0], true],
    ], @window.native.popups
  end

  # Window::popup_menu and popup_menu_at call the menu's (window/mod.rs:1365-1379).
  def test_the_window_pops_up_a_menu_or_a_submenu
    menu = Tokra::Menu::Menu.with_id(@handle, "context")
    submenu = Tokra::Menu::Submenu.with_id(@handle, "nested", "Nested", true)

    assert_nil @window.popup_menu(menu)
    assert_nil @window.popup_menu_at(submenu, Tokra::LogicalPosition.new(x: 1, y: 2))

    assert_equal [["context", nil, true], ["nested", [false, 1.0, 2.0], true]], @window.native.popups
  end

  # Tauri's ContextMenu bound takes only a Menu or a Submenu, and Into<Position>
  # only a position; Ruby checks both on the calling thread.
  def test_only_a_menu_or_submenu_pops_up_and_only_at_a_position
    item = Tokra::Menu::MenuItem.with_id(@handle, "plain", "Plain", true, nil)
    menu = Tokra::Menu::Menu.with_id(@handle, "context")

    error = assert_raises(TypeError) { @window.popup_menu(item) }
    assert_equal "wrong argument type Tokra::Menu::MenuItem (expected Tokra::Menu::ContextMenu)", error.message
    assert_raises(TypeError) { @window.popup_menu_at(item, Tokra::LogicalPosition.new(x: 1, y: 2)) }
    error = assert_raises(TypeError) { menu.popup_at(@window, [1, 2]) }
    assert_equal "wrong argument type Array (expected Tokra::LogicalPosition or Tokra::PhysicalPosition)", error.message
    error = assert_raises(TypeError) { menu.popup(@window.native) }
    assert_equal "wrong argument type StubWindowsMenusNative::Window (expected Tokra::Window)", error.message
    assert_empty @window.native.popups
  end

  # Tauri's popup_inner does nothing for a window without its platform
  # view (menu/menu.rs:49-79); a closed window has none (plan 038).
  def test_a_closed_window_shows_no_menu
    @window.native.close

    assert_nil Tokra::Menu::Menu.with_id(@handle, "context").popup(@window)
    assert_empty @window.native.popups
  end

  # run_item_main_thread! sends the popup to the main thread and waits for
  # it, failing to receive when the loop ends first (menu/mod.rs:25-39).
  def test_a_popup_from_another_thread_runs_on_the_main_thread_and_waits_for_it
    menu = Tokra::Menu::Menu.with_id(@handle, "context")
    context = @handle.runtime_context
    context.attach(StubNative::Proxy.new)

    asked = Thread.new { menu.popup_at(@window, Tokra::PhysicalPosition.new(x: 7, y: 8)) }
    Thread.pass until context.instance_variable_get(:@tasks).any?
    assert_empty @window.native.popups, "the popup waits for the main thread"
    context.handle_task
    assert_nil asked.value
    assert_equal [["context", [true, 7.0, 8.0], true]], @window.native.popups

    waiting = Thread.new do
      Thread.current.report_on_exception = false
      menu.popup(@window)
    end
    Thread.pass until context.instance_variable_get(:@tasks).any?
    context.close
    assert_raises(Tokra::Error::FailedToReceiveMessage) { waiting.value }
  end

  # Tauri's set_theme themes the window's menu on Windows with
  # map_to_menu_theme, Auto for None (window/mod.rs:2185-2206).
  def test_on_windows_set_theme_themes_the_windows_menu_bar
    @window.set_theme(Tokra::Theme::Dark)
    assert_empty @window.native.menu_theme_calls, "a window without a menu has none to theme"

    @window.set_menu(Tokra::Menu::Menu.with_id(@handle, "bar"))
    assert_nil @window.set_theme(Tokra::Theme::Dark)
    assert_nil @window.set_theme(Tokra::Theme::Light)
    assert_nil @window.set_theme(nil)

    assert_equal [%w[bar Dark], %w[bar Light], ["bar", nil]], @window.native.menu_theme_calls
    assert_equal [nil], @window.native.requests[:set_theme], "the window takes its theme too"
  end

  # Off Windows the native window has no set_menu_theme, as Tauri's cfg
  # has it, so set_theme touches only the window.
  def test_elsewhere_set_theme_leaves_the_menu_alone
    skip "on Windows every native window themes its menu" if Tokra::Native::Window.method_defined?(:set_menu_theme)

    window = Tokra::Window.new(label: "main", native: StubWindowMenusNative::Window.new(nil), app_handle: @handle)
    window.set_menu(Tokra::Menu::Menu.with_id(@handle, "bar"))

    assert_nil window.set_theme(Tokra::Theme::Dark)
    refute_respond_to window.native, :set_menu_theme
  end

  # Tauri's hpopupmenu exists only on Windows (menu/mod.rs:741-743).
  def test_hpopupmenu_is_the_windows_handle_and_windows_only
    menu = Tokra::Menu::Menu.with_id(@handle, "context")
    submenu = Tokra::Menu::Submenu.with_id(@handle, "nested", "Nested", true)
    windows = RbConfig::CONFIG["host_os"].match?(/mswin|mingw|cygwin/)

    assert_equal windows, menu.respond_to?(:hpopupmenu)
    assert_equal windows, submenu.respond_to?(:hpopupmenu)
    skip "HMENU is Windows'" unless windows

    assert_operator menu.hpopupmenu, :>, 0
    assert_operator submenu.hpopupmenu, :>, 0
    refute_equal menu.hpopupmenu, submenu.hpopupmenu
  end
end
