# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../support/native_event_loop"

# The native tray class against the real extension and tray-icon 0.21.0
# (plan 043, decision 1). A tray needs the event loop, which on Linux
# needs a display; on macOS each tray shows in the menu bar until it is
# removed, and takes no focus. No test here opens a tray's menu.
class TestNativeTray < Minitest::Test
  ICON = ("\x20\x80\xE0\xFF".b * 256)

  def linux? = RbConfig::CONFIG["host_os"].include?("linux")

  def tray(id = "native-tray", **attributes)
    reason = NativeEventLoop.unavailable_reason
    skip reason if reason
    NativeEventLoop.shared
    Tokra::Native::TrayIcon.new(id, attributes.transform_keys(&:to_s)).tap { |made| (@trays ||= []) << made }
  end

  def teardown
    @trays&.each(&:remove)
  end

  def test_next_id_takes_consecutive_numbers_from_tray_icons_counter
    first = Integer(Tokra::Native::TrayIcon.next_id)

    assert_equal first + 1, Integer(Tokra::Native::TrayIcon.next_id)
  end

  # tray-icon's own checks, run first in 64 bits with its texts (plan 043,
  # decision 8).
  def test_an_icon_is_refused_in_tray_icons_words_before_its_product_can_wrap
    error = assert_raises(RuntimeError) { Tokra::Native::TrayIcon::Icon.from_rgba("\x00".b * 4, 65_536, 65_536) }
    assert_equal "The specified dimensions (65536x65536) don't match the number of pixels supplied by the `rgba` " \
      "argument (1). For those dimensions, the expected pixel count is 4294967296.", error.message
    error = assert_raises(RuntimeError) { Tokra::Native::TrayIcon::Icon.from_rgba("\x00".b * 3, 1, 1) }
    assert_equal "The length of the `rgba` argument (3) isn't divisible by 4, making it impossible to interpret as " \
      "32bpp RGBA pixels.", error.message
    assert_instance_of Tokra::Native::TrayIcon::Icon, Tokra::Native::TrayIcon::Icon.from_rgba(ICON, 16, 16)
  end

  # A tray before any event loop exists would make an AppIndicator before
  # GTK, or a status item before tao's NSApp (plan 043, decision 3). This
  # process may already hold a loop, so a fresh one asks.
  def test_a_tray_before_any_event_loop_is_refused
    script = <<~RUBY
      require "tokra"
      begin
        Tokra::Native::TrayIcon.new("early", {})
      rescue RuntimeError => e
        print e.message
      end
    RUBY
    out, status = Open3.capture2e(RbConfig.ruby, "-I", File.expand_path("../../lib", __dir__), "-e", script)

    assert status.success?, out
    assert_equal "no event loop exists yet; build tray icons once App#run has built it, such as in the setup hook", out
  end

  def test_a_tray_keeps_its_id_and_takes_every_attribute
    reason = NativeEventLoop.unavailable_reason
    skip reason if reason
    menu = Tokra::Native::Menu.with_id("native-tray-menu")
    menu.append(Tokra::Native::MenuItem.with_id("native-tray-item", "Item", true, nil))
    icon = Tokra::Native::TrayIcon::Icon.from_rgba(ICON, 16, 16)

    made = tray("native-full", menu:, icon:, tooltip: "Tip", title: "Title", icon_is_template: true,
      menu_on_left_click: false, temp_dir_path: Dir.tmpdir)

    assert_equal "native-full", made.id
    refute made.removed?
  end

  def test_the_setters_answer_nil_and_change_the_tray
    made = tray
    icon = Tokra::Native::TrayIcon::Icon.from_rgba(ICON, 16, 16)
    submenu = Tokra::Native::Submenu.new("More", true)

    assert_nil made.set_icon(icon)
    assert_nil made.set_icon(nil)
    assert_nil made.set_menu(submenu)
    assert_nil made.set_tooltip("Tip")
    assert_nil made.set_tooltip(nil)
    assert_nil made.set_title("Title")
    assert_nil made.set_visible(false)
    assert_nil made.set_visible(true)
    assert_nil made.set_icon_as_template(true) if made.respond_to?(:set_icon_as_template)
    assert_nil made.set_show_menu_on_left_click(false) if made.respond_to?(:set_show_menu_on_left_click)
    assert_nil made.set_temp_dir_path(nil) if made.respond_to?(:set_temp_dir_path)
  end

  def test_a_menu_must_be_a_native_menu_or_submenu
    made = tray

    error = assert_raises(TypeError) { made.set_menu(Tokra::Native::MenuItem.new("Item", true, nil)) }
    assert_equal "wrong argument type Tokra::Native::MenuItem (expected Tokra::Native::Menu or Tokra::Native::Submenu)",
      error.message
    assert_raises(TypeError) { tray("native-bad-menu", menu: "menu") }
  end

  # tray-icon's PNG encoder refuses an image with no pixels on macOS and
  # Linux; Windows' CreateIcon refuses it as the icon is made.
  def test_an_icon_with_no_pixels_is_tray_icons_own_error
    made = tray
    if RbConfig::CONFIG["host_os"].match?(/mswin|mingw|cygwin/)
      assert_raises(RuntimeError) { Tokra::Native::TrayIcon::Icon.from_rgba("".b, 0, 0) }
    else
      empty = Tokra::Native::TrayIcon::Icon.from_rgba("".b, 0, 0)
      error = assert_raises(RuntimeError) { made.set_icon(empty) }
      assert_match(/zero width/i, error.message)
    end
  end

  def test_rect_is_four_integers_where_tray_icon_has_one
    rect = tray.rect

    if linux?
      assert_nil rect, "tray-icon's GTK tray has no rect"
    else
      assert_equal 4, rect.size
      assert(rect.all?(Integer))
    end
  end

  # Removing drops tray-icon's tray; after it, each call does nothing
  # (plan 043, decision 6).
  def test_a_removed_tray_does_nothing
    made = tray("native-removed")

    assert_nil made.remove
    assert made.removed?
    assert_nil made.rect
    assert_nil made.set_tooltip("gone")
    assert_nil made.set_visible(true)
    assert_nil made.remove
    assert_equal "native-removed", made.id
  end

  def test_a_tray_is_made_and_used_only_on_the_main_thread
    made = tray

    built = Thread.new do
      Thread.current.report_on_exception = false
      Tokra::Native::TrayIcon.new("other-thread", {})
    end
    error = assert_raises(ThreadError) { built.value }
    assert_equal "Tokra::Native::TrayIcon can only be created on the main thread", error.message
    used = Thread.new do
      Thread.current.report_on_exception = false
      made.set_tooltip("x")
    end
    assert_raises(ThreadError) { used.value }
  end

  # tray-icon writes the icon into the temp directory, a new file for each
  # icon, and removes the last as the tray drops
  # (platform_impl/gtk/mod.rs:23-116).
  def test_on_linux_the_icon_is_a_file_in_the_temp_directory
    skip "only Linux's tray-icon writes its icon to a file" unless linux?

    Dir.mktmpdir do |dir|
      made = tray("native-file", icon: Tokra::Native::TrayIcon::Icon.from_rgba(ICON, 16, 16), temp_dir_path: dir)
      first = Dir.children(dir)
      assert_equal 1, first.size
      assert_match(/\Atray-icon-\d+-0\.png\z/, first.first)
      assert_equal "\x89PNG".b, File.binread(File.join(dir, first.first), 4)

      made.set_icon(Tokra::Native::TrayIcon::Icon.from_rgba(ICON, 16, 16))
      second = Dir.children(dir)
      assert_equal 1, second.size
      assert_match(/-1\.png\z/, second.first)

      made.remove
      assert_empty Dir.children(dir)
    end
  end

  # muda's GTK context menu panics on an accelerator GTK has no key for,
  # and tray-icon builds it to attach the menu; the native layer raises
  # muda's error first (plan 043, decision 8).
  def test_on_linux_a_menu_gtk_cannot_build_is_refused_before_tray_icon_builds_it
    skip "only GTK builds a context menu for the tray" unless linux?

    menu = Tokra::Native::Menu.new
    menu.append(Tokra::Native::MenuItem.new("Add", true, "NumpadAdd"))
    made = tray

    error = assert_raises(RuntimeError) { made.set_menu(menu) }
    assert_match(/Couldn't recognize "NumpadAdd" as a valid key for accelerator/, error.message)
    assert_raises(RuntimeError) { Tokra::Native.refuse_unbuildable_menu(menu) }
    assert_raises(RuntimeError) { tray("native-numpad", menu:) }
  end

  # Ruby asks the native check first, inside the tray's main-thread call,
  # so the refusal is muda's Error::Menu, not a tray error (plan 043,
  # decision 8).
  def test_on_linux_ruby_raises_error_menu_for_a_menu_gtk_cannot_build
    skip "only GTK builds a context menu for the tray" unless linux?

    handle = Tokra::Builder.default.build.handle
    menu = Tokra::Menu::MenuBuilder.new(handle)
      .item(Tokra::Menu::MenuItemBuilder.new("Add").accelerator("NumpadAdd").build(handle)).build

    error = assert_raises(Tokra::Error::Menu) { Tokra::Tray.refuse_unbuildable_menu(handle, menu.native) }
    assert_match(/\Amenu error: Couldn't recognize "NumpadAdd"/, error.message)
    assert_nil Tokra::Tray.refuse_unbuildable_menu(handle, nil)
  end
end
