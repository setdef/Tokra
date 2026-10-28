# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fiddle"
require_relative "platform_menu"

# Finds, reads, and closes a real context menu while it tracks the
# pointer, for the context-menu fixture (plan 042, phase 3). Nothing here
# clicks or types: a menu closes through AppKit's own calls
# (-[NSMenu performActionForItemAtIndex:], -[NSMenu cancelTracking]),
# GTK's (gtk_menu_shell_activate_item, gtk_menu_shell_cancel), or
# Win32's (WM_CANCELMODE, EndMenu).
#
# A popup runs a nested loop on the main thread, so the main thread runs
# Ruby only from a timer the platform's loop fires: a CFRunLoopTimer in
# the common modes on macOS, a GLib timeout on Linux (g_timeout_add,
# which any thread may call), a Win32 timer on Windows (SetTimer, on the
# thread that owns the window). Another thread reaches a macOS menu
# through GCD's main queue. Fiddle takes
# the GVL back for such a callback when the popup has released it.
module PlatformPopup
  # Each callback Fiddle made, kept alive while the platform may call it.
  CALLBACKS = Thread::Queue.new

  # Calls the block on the main thread every +interval+ milliseconds until
  # it returns false. Call it on the main thread.
  def self.every(window, interval, &)
    case Tokra::Menu.os
    when :macos then Appkit.every(interval, &)
    when :windows then Win32.every(window.window_handle.hwnd, interval, &)
    else Gtk.every(interval, &)
    end
  end

  # The open context menu whose items are titled +labels+, or +nil+:
  # macOS's tracked NSMenu, Linux's GtkMenu, or Windows' menu window.
  # +shown+ false finds a menu that is not showing too.
  def self.find(labels, shown: true)
    case Tokra::Menu.os
    when :macos then Appkit.find(labels, shown:)
    when :windows then Win32.find
    else Gtk.find(labels, shown:)
    end
  end

  # The titles of +menu+'s items, as the platform holds them.
  def self.labels(menu, context_menu)
    case Tokra::Menu.os
    when :macos then Appkit.labels(menu)
    when :windows then Win32.labels(context_menu)
    else Gtk.labels(menu)
    end
  end

  # The menu's top-left corner relative to the window's, in physical
  # pixels. +place+ is the window's inner position and scale factor, read
  # before the popup, for macOS.
  def self.offset(window, menu, title, place)
    case Tokra::Menu.os
    when :macos then Appkit.offset(*place, menu)
    when :windows then Win32.offset(window.window_handle.hwnd, menu)
    else Gtk.offset(title, menu)
    end
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

  # AppKit's context menus. -[NSMenu popUpMenuPositioningItem:atLocation:
  # inView:] tracks in NSEventTrackingRunLoopMode, one of the main run
  # loop's common modes, so a CFRunLoopTimer added in the common modes
  # fires while the menu tracks, and so does a block on GCD's main queue,
  # which the run loop drains in its common modes too. AppKit names the
  # menu it tracks in NSMenuDidBeginTrackingNotification, which reaches an
  # observer of CoreFoundation's local center, the same center as
  # -[NSNotificationCenter defaultCenter]. The menu's window is a window
  # of this process at the pop-up menu level, which CGWindowList finds
  # without the screen-recording permission, since it asks only for
  # bounds, owners, and levels.
  module Appkit
    FOUNDATION = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"
    GRAPHICS = "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
    # CFStringBuiltInEncodings, CFNumberType, and CFNotificationSuspension
    # Behavior (CFString.h, CFNumber.h, CFNotificationCenter.h).
    UTF8 = 0x08000100
    INT = 9
    DELIVER_IMMEDIATELY = 4
    # kCGPopUpMenuWindowLevelKey's level (CGWindowLevel.h).
    POP_UP_MENU_LEVEL = 101

    def self.cf
      @cf ||= Fiddle.dlopen(FOUNDATION)
    end

    def self.cg
      @cg ||= Fiddle.dlopen(GRAPHICS)
    end

    def self.libdispatch
      @libdispatch ||= Fiddle.dlopen("/usr/lib/system/libdispatch.dylib")
    end

    def self.fn(library, name, args, ret = Fiddle::TYPE_VOIDP)
      Fiddle::Function.new(library[name], args, ret)
    end

    # The value of a global CFStringRef constant, such as
    # kCFRunLoopCommonModes.
    def self.constant(library, name)
      Fiddle::Pointer.new(library[name]).ptr
    end

    def self.string(text)
      fn(cf, "CFStringCreateWithCString", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT])
        .call(nil, text, UTF8)
    end

    # The menu AppKit is tracking, or +nil+ when it tracks none.
    def self.tracking
      @tracking
    end

    # Starts remembering each menu AppKit begins to track, and forgetting
    # it once AppKit ends tracking it, so a later lookup never messages a
    # menu that may be gone. Call it once, on the main thread.
    def self.observe
      return if @observer

      @observer = Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_VOID, Array.new(5) { Fiddle::TYPE_VOIDP }) do |*, menu, _|
        @tracking = menu
      end
      @end_observer = Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_VOID, Array.new(5) { Fiddle::TYPE_VOIDP }) do |*, menu, _|
        @tracking = nil if @tracking && @tracking.to_i == menu.to_i
      end
      center = fn(cf, "CFNotificationCenterGetLocalCenter", []).call
      add = fn(cf, "CFNotificationCenterAddObserver", ([Fiddle::TYPE_VOIDP] * 5) + [Fiddle::TYPE_LONG], Fiddle::TYPE_VOID)
      add.call(center, @observer, @observer, string("NSMenuDidBeginTrackingNotification"), nil, DELIVER_IMMEDIATELY)
      add.call(center, @end_observer, @end_observer, string("NSMenuDidEndTrackingNotification"), nil, DELIVER_IMMEDIATELY)
    end

    # A CFRunLoopTimer on the main run loop's common modes.
    def self.every(interval, &block)
      seconds = interval / 1000.0
      timer = nil
      callback = Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_VOID, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP]) do
        fn(cf, "CFRunLoopTimerInvalidate", [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID).call(timer) unless block.call
      end
      CALLBACKS << callback
      now = fn(cf, "CFAbsoluteTimeGetCurrent", [], Fiddle::TYPE_DOUBLE).call
      timer = fn(cf, "CFRunLoopTimerCreate", [
        Fiddle::TYPE_VOIDP,
        Fiddle::TYPE_DOUBLE,
        Fiddle::TYPE_DOUBLE,
        Fiddle::TYPE_LONG,
        Fiddle::TYPE_LONG,
        Fiddle::TYPE_VOIDP,
        Fiddle::TYPE_VOIDP,
], Fiddle::TYPE_VOIDP).call(nil, now + seconds, seconds, 0, 0, callback, nil)
      fn(cf, "CFRunLoopAddTimer", [Fiddle::TYPE_VOIDP] * 3, Fiddle::TYPE_VOID)
        .call(fn(cf, "CFRunLoopGetMain", []).call, timer, constant(cf, "kCFRunLoopCommonModes"))
    end

    # Runs the block on the main thread through GCD's main queue, from any
    # thread.
    def self.on_main_queue(&block)
      callback = Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_VOID, [Fiddle::TYPE_VOIDP]) { |_| block.call }
      CALLBACKS << callback
      fn(libdispatch, "dispatch_async_f", [Fiddle::TYPE_VOIDP] * 3, Fiddle::TYPE_VOID)
        .call(libdispatch["_dispatch_main_q"], nil, callback)
    end

    # The tracked menu whose items are titled +labels+, once its window is
    # on screen; with +shown+ false, whether or not it is.
    def self.find(labels, shown:)
      menu = tracking
      return nil unless menu && self.labels(menu) == labels
      return menu unless shown

      menu_bounds ? menu : nil
    end

    def self.labels(menu)
      PlatformMenu::Appkit.items(menu).map { |item| PlatformMenu::Appkit.title(item) }
    end

    # Chooses the item titled +title+ through the menu's own dispatch.
    def self.activate(menu, title)
      index = labels(menu).index(title)
      PlatformMenu::Appkit.msg(menu, "performActionForItemAtIndex:", index)
    end

    def self.cancel(menu)
      PlatformMenu::Appkit.msg(menu, "cancelTracking", ret: Fiddle::TYPE_VOID)
    end

    # The menu window's top-left corner relative to +origin+, the window's
    # inner position, in physical pixels. CGWindowList answers points from
    # the main display's top-left corner, as tao's positions are measured.
    def self.offset(origin, scale, _menu)
      x, y = menu_bounds
      [(x * scale).round - origin.x, (y * scale).round - origin.y]
    end

    # The x and y of this process's on-screen pop-up menu window, or +nil+.
    def self.menu_bounds
      list = fn(cg, "CGWindowListCopyWindowInfo", [Fiddle::TYPE_UINT, Fiddle::TYPE_UINT]).call(1, 0)
      count = fn(cf, "CFArrayGetCount", [Fiddle::TYPE_VOIDP], Fiddle::TYPE_LONG).call(list)
      get = fn(cf, "CFArrayGetValueAtIndex", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG])
      Array.new(count) { |index| get.call(list, index) }.each do |info|
        next unless number(info, "kCGWindowOwnerPID") == Process.pid &&
          number(info, "kCGWindowLayer") == POP_UP_MENU_LEVEL

        rect = Fiddle::Pointer.malloc(32, Fiddle::RUBY_FREE)
        fn(cg, "CGRectMakeWithDictionaryRepresentation", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
          .call(value(info, "kCGWindowBounds"), rect)
        return rect[0, 16].unpack("d2")
      end
      nil
    ensure
      fn(cf, "CFRelease", [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID).call(list) if list
    end

    def self.value(info, key)
      fn(cf, "CFDictionaryGetValue", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP]).call(info, constant(cg, key))
    end

    def self.number(info, key)
      out = Fiddle::Pointer.malloc(4, Fiddle::RUBY_FREE)
      fn(cf, "CFNumberGetValue", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
        .call(value(info, key), INT, out)
      out[0, 4].unpack1("l")
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
