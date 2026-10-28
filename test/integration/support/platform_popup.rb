# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fiddle"
require_relative "platform_menu"

# Finds, reads, and closes a real context menu while it tracks the
# pointer, for the context-menu fixture (plan 042, phase 3), on Linux and
# Windows only. Nothing here clicks or types: a menu closes through GTK's
# own calls (gtk_menu_shell_activate_item, gtk_menu_shell_cancel) or
# Win32's (WM_CANCELMODE, EndMenu).
#
# A popup runs a nested loop on the main thread, so the main thread runs
# Ruby only from a timer the platform's loop fires: a GLib timeout on
# Linux (g_timeout_add, which any thread may call), a Win32 timer on
# Windows (SetTimer, on the thread that owns the window). Fiddle takes
# the GVL back for such a callback when the popup has released it.
module PlatformPopup
  # Each callback Fiddle made, kept alive while the platform may call it.
  CALLBACKS = Thread::Queue.new

  # Calls the block on the main thread every +interval+ milliseconds until
  # it returns false. Call it on the main thread.
  def self.every(window, interval, &)
    if Tokra::Menu.os == :windows
      Win32.every(window.window_handle.hwnd, interval, &)
    else
      Gtk.every(interval, &)
    end
  end

  # The open context menu whose items are titled +labels+, or +nil+:
  # Linux's GtkMenu, or Windows' menu window. +shown+ false finds a
  # GtkMenu that is not showing too.
  def self.find(labels, shown: true)
    (Tokra::Menu.os == :windows) ? Win32.find : Gtk.find(labels, shown:)
  end

  # The titles of +menu+'s items, as the platform holds them.
  def self.labels(menu, context_menu)
    (Tokra::Menu.os == :windows) ? Win32.labels(context_menu) : Gtk.labels(menu)
  end

  # The menu's top-left corner relative to the window's, in physical
  # pixels.
  def self.offset(window, menu, title)
    (Tokra::Menu.os == :windows) ? Win32.offset(window.window_handle.hwnd, menu) : Gtk.offset(title, menu)
  end

  # GLib's and GTK's context menus.
  module Gtk
    def self.glib
      @glib ||= Fiddle.dlopen("libglib-2.0.so.0")
    end

    def self.fn(name, args, ret = Fiddle::TYPE_VOIDP)
      PlatformMenu::Gtk.fn(name, args, ret)
    end

    def self.every(interval, &block)
      callback = Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_INT, [Fiddle::TYPE_VOIDP]) { |_| block.call ? 1 : 0 }
      CALLBACKS << callback
      Fiddle::Function.new(glib["g_timeout_add"], [Fiddle::TYPE_UINT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
        Fiddle::TYPE_UINT).call(interval, callback, nil)
    end

    # GTK keeps a menu in a popup GtkWindow of its own.
    def self.find(labels, shown:)
      gtk = PlatformMenu::Gtk
      gtk.list(fn("gtk_window_list_toplevels", []).call).each do |top|
        menu = fn("gtk_bin_get_child", [Fiddle::TYPE_VOIDP]).call(top)
        next if menu.null? || gtk.type_name(menu) != "GtkMenu" || self.labels(menu) != labels
        return menu if !shown || fn("gtk_widget_get_mapped", [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT).call(menu) != 0
      end
      nil
    end

    def self.labels(menu)
      PlatformMenu::Gtk.children(menu).map { |item| PlatformMenu::Gtk.label(item) }
    end

    def self.activate(menu, title)
      item = PlatformMenu::Gtk.children(menu).find { |child| PlatformMenu::Gtk.label(child) == title }
      fn("gtk_menu_shell_activate_item", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_VOID)
        .call(menu, item, 1)
    end

    def self.cancel(menu)
      fn("gtk_menu_shell_cancel", [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID).call(menu)
    end

    def self.offset(title, menu)
      main = origin(PlatformMenu::Gtk.window(title))
      popup = origin(fn("gtk_widget_get_toplevel", [Fiddle::TYPE_VOIDP]).call(menu))
      [popup[0] - main[0], popup[1] - main[1]]
    end

    def self.origin(widget)
      gdk_window = fn("gtk_widget_get_window", [Fiddle::TYPE_VOIDP]).call(widget)
      xy = Fiddle::Pointer.malloc(8, Fiddle::RUBY_FREE)
      gdk = Fiddle.dlopen("libgdk-3.so.0")
      Fiddle::Function.new(gdk["gdk_window_get_origin"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
        Fiddle::TYPE_INT).call(gdk_window, xy, xy + 4)
      xy[0, 8].unpack("l2")
    end
  end

  # Win32's menu window and timers.
  module Win32
    WM_CANCELMODE = 0x1F

    def self.fn(name, args, ret)
      PlatformMenu::Win32.fn(name, args, ret)
    end

    def self.every(hwnd, interval, &block)
      kill = fn("KillTimer", [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_UINTPTR_T], Fiddle::TYPE_INT)
      callback = Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_VOID,
        [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_UINT, Fiddle::TYPE_UINTPTR_T, Fiddle::TYPE_UINT]) do |window, _, id, _|
        kill.call(window, id) unless block.call
      end
      CALLBACKS << callback
      @next_id = (@next_id || 0x7000) + 1
      fn("SetTimer", [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_UINTPTR_T, Fiddle::TYPE_UINT, Fiddle::TYPE_VOIDP],
        Fiddle::TYPE_UINTPTR_T).call(hwnd, @next_id, interval, callback)
    end

    # The visible menu window, class "#32768", that TrackPopupMenu shows.
    def self.find
      window = fn("FindWindowW", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INTPTR_T)
        .call("#32768\0".encode("UTF-16LE"), nil)
      return nil if window.zero?

      fn("IsWindowVisible", [Fiddle::TYPE_INTPTR_T], Fiddle::TYPE_INT).call(window).zero? ? nil : window
    end

    def self.labels(hmenu)
      PlatformMenu::Win32.tree(nil, hmenu).map(&:first)
    end

    # Posted from any thread: the menu loop dispatches it to the window,
    # and DefWindowProc ends the menu.
    def self.cancel(hwnd)
      fn("PostMessageW", [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_INT, Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_INTPTR_T],
        Fiddle::TYPE_INT).call(hwnd, WM_CANCELMODE, 0, 0)
    end

    # Ends the calling thread's menu, from a timer on the main thread.
    def self.end_menu
      fn("EndMenu", [], Fiddle::TYPE_INT).call
    end

    def self.offset(hwnd, menu_window)
      rect = Fiddle::Pointer.malloc(16, Fiddle::RUBY_FREE)
      fn("GetWindowRect", [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT).call(menu_window, rect)
      point = Fiddle::Pointer.malloc(8, Fiddle::RUBY_FREE)
      point[0, 8] = [0, 0].pack("l2")
      fn("ClientToScreen", [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT).call(hwnd, point)
      left, top = rect[0, 8].unpack("l2")
      x, y = point[0, 8].unpack("l2")
      [left - x, top - y]
    end
  end
end
