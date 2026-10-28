# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/stub_native"

# Menu icons through a real App and AppHandle with real muda items
# (plan 042, phase 2): IconMenuItem, NativeIcon, Submenu's icons, the
# builders' icon methods, and the menu plugin's icon payloads.
class TestMenuIcons < Minitest::Test
  # A 2x2 image, all opaque white.
  WHITE = Tokra::Image.new(rgba: "\xFF".b * 16, width: 2, height: 2)

  # An image whose bytes make one pixel, not the four its size says.
  SHORT = Tokra::Image.new(rgba: "\xFF".b * 4, width: 2, height: 2)

  # muda's text for SHORT (muda 0.17.1 src/icon.rs:52-60).
  SHORT_TEXT = "The specified dimensions (2x2) don't match the number of pixels supplied by the `rgba` " \
    "argument (1). For those dimensions, the expected pixel count is 4."

  def setup
    @handle = Tokra::Builder.default.build(native: StubNative).handle
  end

  def teardown
    StubNative.clear_event
  end

  def test_native_icon_is_tauris_fifty_six_and_nothing_else
    names = Tokra::Menu::NativeIcon.constants.map { |name| Tokra::Menu::NativeIcon.const_get(name) }
      .grep(Tokra::Menu::NativeIcon).map(&:name)

    assert_equal Tokra::Menu::Plugin::NATIVE_ICONS.sort, names.sort
    assert_equal 56, names.size
    assert_equal "LockLocked", Tokra::Menu::NativeIcon::LockLocked.name
    assert_raises(NoMethodError) { Tokra::Menu::NativeIcon.new(name: "Bogus") }
  end

  def test_an_icon_item_keeps_its_id_text_and_state_and_comes_back_from_a_menu_as_itself
    item = Tokra::Menu::IconMenuItem.with_id(@handle, "lock", "Lock", false, WHITE, "CmdOrCtrl+L")
    native = Tokra::Menu::IconMenuItem.with_id_and_native_icon(@handle, :trash, "Trash", true,
      Tokra::Menu::NativeIcon::TrashFull, nil)
    menu = Tokra::Menu::Submenu.with_items(@handle, "Tools", true, [
      item,
      native,
      Tokra::Menu::IconMenuItem.new(@handle, "Plain", true, nil, nil),
      Tokra::Menu::IconMenuItem.with_native_icon(@handle, "Home", true, Tokra::Menu::NativeIcon::Home, nil),
])

    assert_equal ["lock", "Lock", false], [item.id.to_s, item.text, item.is_enabled]
    assert_equal "trash", native.id.to_s
    back = menu.items
    assert_equal [Tokra::Menu::IconMenuItem] * 4, back.map(&:class)
    assert_equal item, back.first
    assert_same back.first, back.first.kind
    item.set_text("Unlock")
    item.set_enabled(true)
    assert_nil item.set_accelerator("CmdOrCtrl+U")
    assert_equal ["Unlock", true], [menu.get("lock").text, menu.get("lock").is_enabled]
    assert_nil item.set_icon(nil)
    assert_nil item.set_icon(WHITE)
    assert_nil item.set_native_icon(Tokra::Menu::NativeIcon::Share)
    assert_nil item.set_native_icon(nil)
  end

  # Tauri converts the image before it makes the item (menu/icon.rs:35-38,
  # image/mod.rs:141-146), and its submenu constructors unwrap muda's error
  # (menu/submenu.rs:122-124); Tokra raises BadMenuIcon for both.
  def test_an_image_muda_refuses_raises_bad_menu_icon_in_mudas_words
    submenu = Tokra::Menu::Submenu.new(@handle, "S", true)
    item = Tokra::Menu::IconMenuItem.new(@handle, "I", true, nil, nil)
    attempts = {
      "IconMenuItem.new" => -> { Tokra::Menu::IconMenuItem.new(@handle, "I", true, SHORT, nil) },
      "IconMenuItem.with_id" => -> { Tokra::Menu::IconMenuItem.with_id(@handle, "i", "I", true, SHORT, nil) },
      "IconMenuItem#set_icon" => -> { item.set_icon(SHORT) },
      "Submenu.new_with_icon" => -> { Tokra::Menu::Submenu.new_with_icon(@handle, "S", true, SHORT) },
      "Submenu.with_id_and_icon" => -> { Tokra::Menu::Submenu.with_id_and_icon(@handle, "s", "S", true, SHORT) },
      "Submenu#set_icon" => -> { submenu.set_icon(SHORT) },
      "PredefinedMenuItem.about" => lambda {
        Tokra::Menu::PredefinedMenuItem.about(@handle, nil, Tokra::Menu::AboutMetadata.new(icon: SHORT))
      },
    }

    attempts.each do |name, attempt|
      error = assert_raises(Tokra::Error::BadMenuIcon, name) { attempt.call }
      assert_equal SHORT_TEXT, error.message, name
    end
    empty = Tokra::Image.new(rgba: "".b, width: 0, height: 0)
    error = assert_raises(Tokra::Error::BadMenuIcon) { Tokra::Menu::IconMenuItem.new(@handle, "I", true, empty, nil) }
    assert_equal "The specified dimensions (0x0) must be greater than zero.", error.message
  end

  def test_a_submenu_takes_an_image_or_a_native_icon_and_keeps_its_id
    with_image = Tokra::Menu::Submenu.with_id_and_icon(@handle, "file", "File", false, WHITE)
    with_native = Tokra::Menu::Submenu.with_id_and_native_icon(@handle, "folder", "Folder", true,
      Tokra::Menu::NativeIcon::Folder)

    assert_equal ["file", "File", false], [with_image.id.to_s, with_image.text, with_image.is_enabled]
    assert_equal "folder", with_native.id.to_s
    assert_equal "Edit", Tokra::Menu::Submenu.new_with_icon(@handle, "Edit", true, nil).text
    assert_equal "View", Tokra::Menu::Submenu.new_with_native_icon(@handle, "View", true, nil).text
    assert_nil with_image.set_icon(nil)
    assert_nil with_native.set_native_icon(Tokra::Menu::NativeIcon::Home)
  end

  # The builders add an enabled item with the id and icon given
  # (builders/menu.rs:252-288).
  def test_the_menu_builders_icon_methods_add_icon_items_and_keep_a_bad_images_error_for_build
    menu = Tokra::Menu::MenuBuilder.new(@handle)
      .icon("lock", "Lock", WHITE)
      .native_icon("home", "Home", Tokra::Menu::NativeIcon::Home)
      .build

    assert_equal [Tokra::Menu::IconMenuItem] * 2, menu.items.map(&:class)
    assert_equal [%w[lock Lock], %w[home Home]], menu.items.map { |item| [item.id.to_s, item.text] }
    assert menu.items.all?(&:is_enabled)
    builder = Tokra::Menu::SubmenuBuilder.new(@handle, "S").icon("bad", "Bad", SHORT)
    error = assert_raises(Tokra::Error::BadMenuIcon) { builder.build }
    assert_equal SHORT_TEXT, error.message
  end

  # #icon and #native_icon each drop the other (builders/icon.rs:73-89),
  # and the submenu builder's do the same (builders/menu.rs:157-171): the
  # last one set decides, so a bad image set first is never converted.
  def test_the_last_icon_a_builder_is_given_wins
    item = Tokra::Menu::IconMenuItemBuilder.with_id("i", "Item").icon(SHORT).native_icon(Tokra::Menu::NativeIcon::Add)
      .enabled(false).accelerator("CmdOrCtrl+I").build(@handle)
    assert_equal ["i", "Item", false], [item.id.to_s, item.text, item.is_enabled]
    assert_raises(Tokra::Error::BadMenuIcon) do
      Tokra::Menu::IconMenuItemBuilder.new("Item").native_icon(Tokra::Menu::NativeIcon::Add).icon(SHORT).build(@handle)
    end
    assert Tokra::Menu::IconMenuItemBuilder.new("Item").build(@handle).is_enabled, "enabled unless told otherwise"

    submenu = Tokra::Menu::SubmenuBuilder.with_id(@handle, "s", "S").submenu_icon(SHORT)
      .submenu_native_icon(Tokra::Menu::NativeIcon::Folder).build
    assert_equal "s", submenu.id.to_s
    assert_raises(Tokra::Error::BadMenuIcon) do
      Tokra::Menu::SubmenuBuilder.new(@handle, "S").submenu_native_icon(Tokra::Menu::NativeIcon::Folder)
        .submenu_icon(SHORT).build
    end
  end

  # Tauri's set_native_icon is macOS's alone (menu/icon.rs:229-237,
  # menu/submenu.rs:430-440): elsewhere it answers at once, without going
  # to the main thread, which a thread with no running loop would fail to
  # reach.
  def test_set_native_icon_does_nothing_where_menus_belong_to_windows
    handle = Tokra::Builder.default.build(native: StubWindowMenusNative).handle
    item = Tokra::Menu::IconMenuItem.new(handle, "I", true, nil, nil)
    submenu = Tokra::Menu::Submenu.new(handle, "S", true)

    answers = Thread.new do
      [item.set_native_icon(Tokra::Menu::NativeIcon::Add), submenu.set_native_icon(Tokra::Menu::NativeIcon::Add)]
    end.value
    assert_equal [nil, nil], answers
  end
end
