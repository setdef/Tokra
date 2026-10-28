# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/native_event_loop"

# The native menu classes, against the real extension and muda 0.17.1
# (plan 042, decision 1). Menus need no window, so most of these run with
# no display; the window menu bar needs one.
class TestNativeMenu < Minitest::Test
  def test_menus_and_items_keep_the_id_they_are_given_or_get_one_from_muda
    assert_equal "app", Tokra::Native::Menu.with_id("app").id
    assert_equal "file", Tokra::Native::Submenu.with_id("file", "File", true).id
    assert_equal "open", Tokra::Native::MenuItem.with_id("open", "Open", true, nil).id
    assert_equal "wrap", Tokra::Native::CheckMenuItem.with_id("wrap", "Wrap", true, false, nil).id

    made = [Tokra::Native::Menu.new.id, Tokra::Native::MenuItem.new("A", true, nil).id]
    made.each { |id| assert_match(/\A\d+\z/, id) }
    refute_equal made.first, made.last
  end

  def test_a_tree_answers_its_items_as_native_objects_in_order
    menu = Tokra::Native::Menu.new
    open = Tokra::Native::MenuItem.with_id("open", "Open", true, nil)
    file = Tokra::Native::Submenu.with_id("file", "File", true)
    quit = Tokra::Native::PredefinedMenuItem.new("quit", nil, nil)
    menu.append(file)
    menu.prepend(open)
    menu.insert(quit, 1)

    items = menu.items

    assert_equal [Tokra::Native::MenuItem, Tokra::Native::PredefinedMenuItem, Tokra::Native::Submenu],
      items.map(&:class)
    assert_equal ["open", quit.id, "file"], items.map(&:id)
    assert_equal "open", menu.remove_at(0).id
    assert_nil menu.remove_at(5)
    assert_equal [quit.id, "file"], menu.items.map(&:id)
  end

  def test_removing_an_item_that_is_not_there_raises_mudas_error
    menu = Tokra::Native::Menu.new
    error = assert_raises(RuntimeError) { menu.remove(Tokra::Native::MenuItem.new("A", true, nil)) }

    assert_equal "This menu item is not a child of this `Menu` or `Submenu`", error.message
  end

  # muda's Vec::insert would panic, and AppKit would raise NSRangeException
  # (plan 042, decision 8).
  def test_a_position_past_the_end_raises_index_error_with_rusts_text
    menu = Tokra::Native::Menu.new
    menu.append(Tokra::Native::MenuItem.new("A", true, nil))

    error = assert_raises(IndexError) { menu.insert(Tokra::Native::MenuItem.new("B", true, nil), 2) }

    assert_equal "insertion index (is 2) should be <= len (is 1)", error.message
    assert_equal 1, menu.items.size
    menu.insert(Tokra::Native::MenuItem.new("C", true, nil), 1)
    assert_equal 2, menu.items.size
  end

  # muda's second RefCell borrow would panic (plan 042, decision 8).
  def test_a_submenu_cannot_go_inside_itself
    outer = Tokra::Native::Submenu.new("Outer", true)
    inner = Tokra::Native::Submenu.new("Inner", true)
    outer.append(inner)

    assert_raises(ArgumentError) { outer.append(outer) }
    assert_raises(ArgumentError) { inner.append(outer) }
    assert_raises(ArgumentError) { inner.insert(outer, 0) }
    assert_raises(ArgumentError) { inner.prepend(outer) }
    assert_equal [inner.id], outer.items.map(&:id)
    assert_empty inner.items
  end

  def test_a_menu_takes_only_native_items
    menu = Tokra::Native::Menu.new

    assert_raises(TypeError) { menu.append("item") }
    assert_raises(TypeError) { menu.append(Tokra::Native::Menu.new) }
  end

  def test_items_keep_their_text_enabled_and_checked_state
    item = Tokra::Native::CheckMenuItem.new("Wrap", true, true, "CmdOrCtrl+W")
    item.set_text("Word Wrap")
    item.set_enabled(false)
    item.set_checked(false)

    assert_equal "Word Wrap", item.text
    refute item.is_enabled
    refute item.is_checked
    assert_nil item.set_accelerator("not an accelerator")
    assert_nil item.set_accelerator(nil)
  end

  def test_predefined_items_are_tauris_seventeen
    # Tauri's Predefined variants name them (menu/plugin.rs:73-92).
    kinds = Tokra::Menu::Plugin::PREDEFINED.values.map(&:to_s)

    assert_equal 17, kinds.size

    kinds.each { |kind| assert_kind_of String, Tokra::Native::PredefinedMenuItem.new(kind, nil, nil).id }
    assert_equal "Paste It", Tokra::Native::PredefinedMenuItem.new("paste", "Paste It", nil).text
    assert_raises(ArgumentError) { Tokra::Native::PredefinedMenuItem.new("bring_all_to_front", nil, nil) }
  end

  def test_the_about_item_takes_metadata_and_refuses_a_bad_icon_in_mudas_words
    metadata = { name: "Notes", version: "1.0", authors: ["Ada"], icon: ["\xFF".b * 4, 1, 1] }
    assert_kind_of String, Tokra::Native::PredefinedMenuItem.new("about", nil, metadata).id

    error = assert_raises(RuntimeError) do
      Tokra::Native::PredefinedMenuItem.new("about", nil, { icon: ["\xFF".b * 4, 2, 2] })
    end
    assert_match(/don't match the number of pixels/, error.message)
  end

  def test_menus_are_made_and_used_only_on_the_main_thread
    item = Tokra::Native::MenuItem.new("A", true, nil)

    made = quiet_thread { Tokra::Native::Menu.new }
    assert_raises(ThreadError) { made.value }
    used = quiet_thread { item.text }
    assert_raises(ThreadError) { used.value }
  end

  # A window's own menu bar exists only on Windows and Linux.
  def test_a_window_shows_hides_and_drops_its_menu_bar
    skip "macOS menus belong to the app" unless Tokra::Native::Window.method_defined?(:init_menu)
    reason = NativeEventLoop.unavailable_reason
    skip reason if reason

    window = Tokra::Native::Window.new(NativeEventLoop.shared)
    menu = Tokra::Native::Menu.new
    menu.append(Tokra::Native::Submenu.new("File", true))

    refute window.is_menu_visible(menu)
    window.init_menu(menu, nil)
    assert window.is_menu_visible(menu)
    window.hide_menu(menu)
    refute window.is_menu_visible(menu)
    window.show_menu(menu)
    assert window.is_menu_visible(menu)
    window.remove_menu(menu)
    refute window.is_menu_visible(menu)
    window.init_menu(menu, nil)
    window.close
    refute window.is_menu_visible(menu)
    assert_nil window.init_menu(menu, nil)
  end

  private def quiet_thread(&)
    Thread.new do
      Thread.current.report_on_exception = false
      yield
    end
  end
end
