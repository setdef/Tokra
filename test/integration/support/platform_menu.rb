# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fiddle"

# Reads a real app's menu back from the platform, and activates its items
# through the platform's own dispatch, for the menu fixtures (plan 042):
# -[NSApp mainMenu] and -[NSMenu performActionForItemAtIndex:] on macOS,
# GetMenu and WM_COMMAND on Windows, and the window's GtkMenuBar and
# gtk_menu_item_activate on Linux. Whether an item shows an image is
# -[NSMenuItem image], the item's hbmpItem, or the GtkImage muda packs
# beside its label. Nothing here clicks, types, or brings
# the app to the front. Every method runs on the main thread, which owns
# the menus.
module PlatformMenu
  # The menu tree the platform holds, as <tt>[title, [children]]</tt>
  # pairs; +nil+ when there is no menu. +title+ names the window on Linux.
  def self.tree(window, title)
    case Tokra::Menu.os
    when :macos then Appkit.tree
    when :windows then Win32.tree(window.window_handle.hwnd)
    else Gtk.tree(Gtk.menu_bar(title))
    end
  end

  # Activates the item titled +title+ inside the submenu titled +submenu+
  # through the platform's own dispatch. Answers whether it found the
  # item.
  def self.activate(window, window_title, submenu, title)
    case Tokra::Menu.os
    when :macos then Appkit.activate(submenu, title)
    when :windows then Win32.activate(window.window_handle.hwnd, submenu, title)
    else Gtk.activate(Gtk.menu_bar(window_title), submenu, title)
    end
  end

  # Whether the platform shows an image on the item at +path+: the titles
  # of a top-level submenu and, optionally, of an item inside it. +nil+
  # when there is no such item.
  def self.image?(window, window_title, path)
    case Tokra::Menu.os
    when :macos then Appkit.image?(path)
    when :windows then Win32.image?(window.window_handle.hwnd, path)
    else Gtk.image?(Gtk.menu_bar(window_title), path)
    end
  end

  # -[NSApp mainMenu], read through the Objective-C runtime.
  module Appkit
    def self.objc
      @objc ||= Fiddle.dlopen("/usr/lib/libobjc.A.dylib")
    end

    def self.sel(name)
      Fiddle::Function.new(objc["sel_registerName"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP).call(name)
    end

    def self.msg(receiver, selector, *args, ret: Fiddle::TYPE_VOIDP)
      types = [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP] + args.map { Fiddle::TYPE_LONG }
      Fiddle::Function.new(objc["objc_msgSend"], types, ret).call(receiver, sel(selector), *args)
    end

    def self.main_menu
      klass = Fiddle::Function.new(objc["objc_getClass"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP).call("NSApplication")
      menu = msg(msg(klass, "sharedApplication"), "mainMenu")
      menu.null? ? nil : menu
    end

    def self.items(menu)
      Array.new(msg(menu, "numberOfItems", ret: Fiddle::TYPE_LONG)) { |index| msg(menu, "itemAtIndex:", index) }
    end

    def self.title(item)
      msg(msg(item, "title"), "UTF8String").to_s.force_encoding(Encoding::UTF_8)
    end

    def self.submenu(item)
      menu = msg(item, "submenu")
      menu.null? ? nil : menu
    end

    def self.tree(menu = main_menu)
      menu && items(menu).map { |item| [title(item), (sub = submenu(item)) ? tree(sub) : []] }
    end

    def self.image?(path)
      submenu_item = items(main_menu).find { |item| title(item) == path[0] }
      item = path[1] ? submenu_item && (sub = submenu(submenu_item)) && items(sub).find { |i| title(i) == path[1] } : submenu_item
      item && !msg(item, "image").null?
    end

    def self.activate(submenu_title, title)
      parent = items(main_menu).map { |item| submenu(item) }.compact.find do |menu|
        msg(msg(menu, "title"), "UTF8String").to_s == submenu_title
      end
      index = parent && items(parent).index { |item| title(item) == title }
      return false unless index

      msg(parent, "performActionForItemAtIndex:", index)
      true
    end
  end

  # GetMenu and its strings, read through user32.
  module Win32
    MF_BYPOSITION = 0x400
    WM_COMMAND = 0x111

    def self.user32
      @user32 ||= Fiddle.dlopen("user32")
    end

    def self.fn(name, args, ret)
      Fiddle::Function.new(user32[name], args, ret)
    end

    def self.items(menu)
      count = fn("GetMenuItemCount", [Fiddle::TYPE_INTPTR_T], Fiddle::TYPE_INT).call(menu)
      Array.new([count, 0].max) { |index| index }
    end

    # The item's text without the tab and accelerator muda appends.
    def self.text(menu, index)
      buffer = Fiddle::Pointer.malloc(512 * 2, Fiddle::RUBY_FREE)
      length = fn("GetMenuStringW", [
        Fiddle::TYPE_INTPTR_T,
        Fiddle::TYPE_INT,
        Fiddle::TYPE_VOIDP,
        Fiddle::TYPE_INT,
        Fiddle::TYPE_INT,
], Fiddle::TYPE_INT).call(menu, index, buffer, 512, MF_BYPOSITION)
      buffer.to_str(length * 2).force_encoding(Encoding::UTF_16LE).encode(Encoding::UTF_8).split("\t").first.to_s.delete("&")
    end

    def self.submenu(menu, index)
      sub = fn("GetSubMenu", [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_INT], Fiddle::TYPE_INTPTR_T).call(menu, index)
      sub.zero? ? nil : sub
    end

    def self.tree(hwnd, menu = nil)
      menu ||= fn("GetMenu", [Fiddle::TYPE_INTPTR_T], Fiddle::TYPE_INTPTR_T).call(hwnd)
      return nil if menu.zero?

      items(menu).map { |index| [text(menu, index), (sub = submenu(menu, index)) ? tree(hwnd, sub) : []] }
    end

    # MENUITEMINFOW's size and hbmpItem's offset on 64-bit Windows
    # (winuser.h), and the mask that asks for hbmpItem.
    MENUITEMINFOW_SIZE = 80
    HBMPITEM_OFFSET = 72
    MIIM_BITMAP = 0x80

    def self.image?(hwnd, path)
      bar = fn("GetMenu", [Fiddle::TYPE_INTPTR_T], Fiddle::TYPE_INTPTR_T).call(hwnd)
      return nil if bar.zero?

      index = items(bar).find { |position| text(bar, position) == path[0] }
      menu = bar
      if index && path[1]
        menu = submenu(bar, index)
        index = menu && items(menu).find { |position| text(menu, position) == path[1] }
      end
      index && bitmap?(menu, index)
    end

    def self.bitmap?(menu, index)
      info = Fiddle::Pointer.malloc(MENUITEMINFOW_SIZE, Fiddle::RUBY_FREE)
      info[0, MENUITEMINFOW_SIZE] = "\0" * MENUITEMINFOW_SIZE
      info[0, 8] = [MENUITEMINFOW_SIZE, MIIM_BITMAP].pack("L<L<")
      read = fn("GetMenuItemInfoW", [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP],
        Fiddle::TYPE_INT).call(menu, index, 1, info)
      return nil if read.zero?

      !info[HBMPITEM_OFFSET, 8].unpack1("Q<").zero?
    end

    def self.activate(hwnd, submenu_title, title)
      bar = fn("GetMenu", [Fiddle::TYPE_INTPTR_T], Fiddle::TYPE_INTPTR_T).call(hwnd)
      parent = items(bar).filter_map { |index| text(bar, index) == submenu_title && submenu(bar, index) }.first
      index = parent && items(parent).find { |position| text(parent, position) == title }
      return false unless index

      id = fn("GetMenuItemID", [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_INT], Fiddle::TYPE_INT).call(parent, index)
      fn("PostMessageW", [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_INT, Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_INTPTR_T],
        Fiddle::TYPE_INT).call(hwnd, WM_COMMAND, id, 0)
      true
    end
  end

  # The window's GtkMenuBar, read through GTK 3.
  module Gtk
    def self.lib
      @lib ||= Fiddle.dlopen("libgtk-3.so.0")
    end

    def self.fn(name, args, ret = Fiddle::TYPE_VOIDP)
      Fiddle::Function.new(lib[name], args, ret)
    end

    # The +data+ of each GList node from +list+.
    def self.list(list)
      nodes = []
      until list.null?
        nodes << Fiddle::Pointer.new(list[0, Fiddle::SIZEOF_VOIDP].unpack1("J"))
        list = Fiddle::Pointer.new(list[Fiddle::SIZEOF_VOIDP, Fiddle::SIZEOF_VOIDP].unpack1("J"))
      end
      nodes
    end

    def self.children(container)
      list(fn("gtk_container_get_children", [Fiddle::TYPE_VOIDP]).call(container))
    end

    def self.type_name(widget)
      fn("gtk_widget_get_name", [Fiddle::TYPE_VOIDP]).call(widget).to_s
    end

    def self.window(title)
      list(fn("gtk_window_list_toplevels", []).call).find do |toplevel|
        fn("gtk_window_get_title", [Fiddle::TYPE_VOIDP]).call(toplevel).to_s == title
      end
    end

    # The GtkMenuBar muda put in the window titled +title+, or +nil+.
    def self.menu_bar(title)
      top = window(title)
      box = top && fn("gtk_bin_get_child", [Fiddle::TYPE_VOIDP]).call(top)
      box && !box.null? && children(box).find { |child| type_name(child) == "GtkMenuBar" }
    end

    # The item's text: its label, or for a submenu, whose label muda puts
    # in a box beside its icon, that box's GtkAccelLabel
    # (platform_impl/gtk/mod.rs:1012-1037).
    def self.label(item)
      text = fn("gtk_menu_item_get_label", [Fiddle::TYPE_VOIDP]).call(item)
      text = text.null? ? "" : text.to_s.force_encoding(Encoding::UTF_8).delete("_")
      text.empty? ? boxed_label(item) : text
    end

    def self.boxed_label(item)
      child = fn("gtk_bin_get_child", [Fiddle::TYPE_VOIDP]).call(item)
      return "" if child.null? || type_name(child) != "GtkBox"

      label = children(child).find { |widget| type_name(widget) == "GtkAccelLabel" }
      label ? fn("gtk_label_get_text", [Fiddle::TYPE_VOIDP]).call(label).to_s.force_encoding(Encoding::UTF_8) : ""
    end

    def self.submenu(item)
      menu = fn("gtk_menu_item_get_submenu", [Fiddle::TYPE_VOIDP]).call(item)
      menu.null? ? nil : menu
    end

    def self.tree(menu)
      menu && children(menu).map { |item| [label(item), (sub = submenu(item)) ? tree(sub) : []] }
    end

    # Whether the GtkImage muda packs first in the item's box holds a
    # pixbuf (platform_impl/gtk/mod.rs:1004-1030, 1284-1310).
    def self.image?(menu_bar, path)
      item = menu_bar && children(menu_bar).find { |child| label(child) == path[0] }
      item = item && (sub = submenu(item)) && children(sub).find { |child| label(child) == path[1] } if path[1]
      return nil unless item

      box = fn("gtk_bin_get_child", [Fiddle::TYPE_VOIDP]).call(item)
      return false if box.null? || type_name(box) != "GtkBox"

      image = children(box).first
      !image.nil? && type_name(image) == "GtkImage" && !fn("gtk_image_get_pixbuf", [Fiddle::TYPE_VOIDP]).call(image).null?
    end

    def self.activate(menu_bar, submenu_title, title)
      parent = menu_bar && children(menu_bar).find { |item| label(item) == submenu_title }
      item = parent && children(submenu(parent)).find { |child| label(child) == title }
      return false unless item

      fn("gtk_menu_item_activate", [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID).call(item)
      true
    end
  end
end
