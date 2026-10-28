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

  def test_the_about_item_takes_metadata_with_mudas_icon
    icon = Tokra::Native::MenuIcon.from_rgba("\xFF".b * 4, 1, 1)
    metadata = { name: "Notes", version: "1.0", authors: ["Ada"], icon: }
    assert_kind_of String, Tokra::Native::PredefinedMenuItem.new("about", nil, metadata).id

    assert_raises(TypeError) { Tokra::Native::PredefinedMenuItem.new("about", nil, { icon: ["\xFF".b * 4, 1, 1] }) }
  end

  # muda's checks in muda's words, then the empty icon muda takes but
  # cannot draw (its PNG encoder on macOS, GTK's Pixbuf on Linux), in
  # tao's words (plan 042, decision 13).
  def test_a_menu_icon_is_refused_in_mudas_words_and_an_empty_one_in_taos
    assert_instance_of Tokra::Native::MenuIcon, Tokra::Native::MenuIcon.from_rgba("\xFF".b * 16, 2, 2)

    {
      ["\xFF".b * 5, 1, 1] => "The length of the `rgba` argument (5) isn't divisible by 4, making it impossible to interpret as 32bpp RGBA pixels.",
      ["\xFF".b * 4, 2, 2] => "The specified dimensions (2x2) don't match the number of pixels supplied by the `rgba` argument (1). For those dimensions, the expected pixel count is 4.",
      ["", 0, 0] => "The specified dimensions (0x0) must be greater than zero.",
      ["", 7, 0] => "The specified dimensions (7x0) must be greater than zero.",
      ["\xFF".b * 4, 65_536, 65_536] => "The specified dimensions (65536x65536) don't match the number of pixels supplied by the `rgba` argument (1). For those dimensions, the expected pixel count is 4294967296.",
    }.each do |(rgba, width, height), message|
      error = assert_raises(RuntimeError) { Tokra::Native::MenuIcon.from_rgba(rgba, width, height) }
      assert_equal message, error.message
    end
  end

  # NativeIcon's 56 names, Tauri's (menu/mod.rs:361-474); each goes into a
  # menu, where muda draws it from macOS's named images.
  def test_icon_items_take_an_image_or_any_of_tauris_native_icons
    icon = Tokra::Native::MenuIcon.from_rgba("\xFF".b * 16, 2, 2)
    menu = Tokra::Native::Menu.new
    item = Tokra::Native::IconMenuItem.with_id("lock", "Lock", true, icon, "CmdOrCtrl+L")
    menu.append(item)
    menu.append(Tokra::Native::IconMenuItem.new("None", false, nil, nil))
    Tokra::Menu::Plugin::NATIVE_ICONS.each do |name|
      menu.append(Tokra::Native::IconMenuItem.with_id_and_native_icon("native-#{name}", name, true, name, nil))
    end
    menu.append(Tokra::Native::IconMenuItem.with_native_icon("Plain", true, nil, nil))

    assert_equal 59, menu.items.size
    assert_instance_of Tokra::Native::IconMenuItem, menu.items.first
    assert_equal %w[lock native-Add native-UserGuest], menu.items.values_at(0, 2, 57).map(&:id)
    assert_equal ["Lock", true], [item.text, item.is_enabled]
    item.set_icon(nil)
    item.set_native_icon("TrashFull")
    item.set_icon(icon)
    item.set_native_icon(nil)
    error = assert_raises(ArgumentError) { Tokra::Native::IconMenuItem.with_native_icon("X", true, "Bogus", nil) }
    assert_equal 'unknown native icon: "Bogus"', error.message
    assert_raises(ArgumentError) { item.set_native_icon("Bogus") }
    assert_raises(TypeError) { item.set_icon("\xFF".b * 4) }
  end

  def test_a_submenu_takes_an_icon_and_a_native_icon
    submenu = Tokra::Native::Submenu.with_id("file", "File", true)
    Tokra::Native::Menu.new.append(submenu)

    submenu.set_icon(Tokra::Native::MenuIcon.from_rgba("\xFF".b * 4, 1, 1))
    submenu.set_native_icon("Folder")
    submenu.set_icon(nil)
    submenu.set_native_icon(nil)
    assert_raises(ArgumentError) { submenu.set_native_icon("Bogus") }
  end

  def test_icon_items_are_made_only_on_the_main_thread
    made = quiet_thread { Tokra::Native::IconMenuItem.new("A", true, nil, nil) }
    assert_raises(ThreadError) { made.value }
    icon = quiet_thread { Tokra::Native::MenuIcon.from_rgba("\xFF".b * 4, 1, 1) }
    assert_instance_of Tokra::Native::MenuIcon, icon.value, "muda's icon is made on any thread, as Tauri converts it"
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
