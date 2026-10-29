# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fiddle"

# Reads a real tray icon back from the platform, and sends it events
# through tray-icon's own dispatch, for the tray fixture (plan 043).
#
# On macOS the tray is the NSStatusBarButton inside a visible
# NSStatusBarWindow of this app, holding tray-icon's TaoTrayTarget view;
# its image, tooltip, and title are the button's. Events go to that view's
# mouseEntered:, mouseMoved:, and mouseExited:, each with an event naming
# the status bar window, as AppKit's tracking area would send them; no
# event is posted to the system, no button is pressed, and no menu opens.
#
# On Windows tray-icon's hidden window (class +tray_icon_app+, this
# process's) gets the WM_USER_TRAYICON messages Shell_NotifyIcon would
# post, with the mouse message in +lparam+.
#
# On Linux the AppIndicator reads its icon from the PNG file tray-icon
# writes into the temp directory, so that file is what the platform
# shows; tray-icon sends no events there.
#
# Every method runs on the main thread, which owns the tray.
module PlatformTray
  # What the platform holds for this app's tray: on macOS
  # <tt>{"image" => bool, "tooltip" => text, "title" => text, "menu" =>
  # titles}</tt> for each visible status item, the menu read from
  # -[NSStatusItem menu], which tray-icon sets (macos/mod.rs:65-69,
  # 124-141), without opening it; on Windows tray-icon's windows; on Linux the
  # icon files in +dir+.
  def self.read(dir)
    case Tokra::Menu.os
    when :macos then Appkit.status_items.map { |(window, button)| Appkit.describe(window, button) }
    when :windows then Win32.tray_windows.size
    else Dir.children(dir).sort
    end
  end

  # Sends +kinds+, a list of :enter, :move, :leave, :click_down, :click_up,
  # and :double_click, to the one tray through tray-icon's dispatch, and
  # answers the kinds it sent. macOS sends only the pointer's three, which
  # open nothing; Windows sends each but :move and :leave, which tray-icon
  # derives from the cursor's own movement.
  def self.dispatch(kinds)
    case Tokra::Menu.os
    when :macos then Appkit.dispatch(kinds & %i[enter move leave])
    when :windows then Win32.dispatch(kinds - %i[move leave])
    else []
    end
  end

  # Opens the one tray's menu the way tray-icon does for a click, and
  # returns once the menu closes: -[NSStatusBarButton performClick:] on
  # macOS (platform_impl/macos/mod.rs:467-488), and on Windows the
  # WM_RBUTTONDOWN message Shell_NotifyIcon posts, after which tray-icon
  # sends the click and calls TrackPopupMenu (platform_impl/windows/mod.rs:
  # 286-396). The call keeps the GVL, as the main thread holds it when the
  # platform delivers a real click to tao's loop, so whether other Ruby
  # threads run while the menu tracks is Tokra's doing, not Fiddle's.
  # Answers whether it found the tray. Call it from a platform timer on
  # the main thread, outside tao's handler, as a click arrives.
  def self.open_menu
    case Tokra::Menu.os
    when :macos then Appkit.open_menu
    when :windows then Win32.open_menu
    else false
    end
  end

  # The Objective-C runtime, through Fiddle.
  module Appkit
    # NSEventTypeMouseEntered, NSEventTypeMouseExited, NSEventTypeMouseMoved.
    TYPES = { enter: 8, leave: 9, move: 5 }.freeze
    # TaoTrayTarget's handler for each (platform_impl/macos/mod.rs:405-418).
    SELECTORS = { enter: "mouseEntered:", leave: "mouseExited:", move: "mouseMoved:" }.freeze

    def self.objc
      @objc ||= Fiddle.dlopen("/usr/lib/libobjc.A.dylib")
    end

    def self.fn(name, args, ret)
      Fiddle::Function.new(objc[name], args, ret)
    end

    def self.sel(name)
      fn("sel_registerName", [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP).call(name)
    end

    def self.klass(name)
      fn("objc_getClass", [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP).call(name)
    end

    def self.msg(receiver, selector, *args, ret: Fiddle::TYPE_VOIDP)
      types = [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP] + args.map { |arg| arg.is_a?(Fiddle::Pointer) ? Fiddle::TYPE_VOIDP : Fiddle::TYPE_LONG }
      Fiddle::Function.new(objc["objc_msgSend"], types, ret).call(receiver, sel(selector), *args)
    end

    def self.class_name(object)
      fn("object_getClassName", [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP).call(object).to_s
    end

    def self.text(object)
      object.null? ? nil : msg(object, "UTF8String").to_s.force_encoding(Encoding::UTF_8)
    end

    def self.children(view)
      subviews = msg(view, "subviews")
      Array.new(msg(subviews, "count", ret: Fiddle::TYPE_LONG)) { |index| msg(subviews, "objectAtIndex:", index) }
    end

    # The first view under +view+ whose class is +name+.
    def self.find(view, name)
      return view if class_name(view) == name

      children(view).each do |child|
        found = find(child, name)
        return found if found
      end
      nil
    end

    # <tt>[window, button]</tt> for each visible status item of this app
    # that tray-icon made, in NSApp's order.
    def self.status_items
      windows = msg(msg(klass("NSApplication"), "sharedApplication"), "windows")
      Array.new(msg(windows, "count", ret: Fiddle::TYPE_LONG)) { |index| msg(windows, "objectAtIndex:", index) }
        .select { |window| class_name(window) == "NSStatusBarWindow" && msg(window, "isVisible", ret: Fiddle::TYPE_CHAR) != 0 }
        .filter_map do |window|
          button = find(msg(window, "contentView"), "NSStatusBarButton")
          [window, button] if button && find(button, "TaoTrayTarget")
        end
    end

    def self.describe(window, button)
      {
        "image" => !msg(button, "image").null?,
        "tooltip" => text(msg(button, "toolTip")),
        "title" => text(msg(button, "title")),
        "menu" => menu_titles(msg(msg(window, "statusItem"), "menu")),
      }
    end

    # The titles of +menu+'s items, or +nil+ for no menu. Reading a menu
    # does not open it.
    def self.menu_titles(menu)
      return nil if menu.null?

      Array.new(msg(menu, "numberOfItems", ret: Fiddle::TYPE_LONG)) do |index|
        text(msg(msg(menu, "itemAtIndex:", index), "title"))
      end
    end

    # The event AppKit would send for +type+ in +window+, which tray-icon's
    # handler asks for the window it names:
    # +enterExitEventWithType:...+ for entering and leaving, which takes no
    # other type, and +mouseEventWithType:...+ for moving.
    def self.event(type, window)
      number = msg(window, "windowNumber", ret: Fiddle::TYPE_LONG)
      head = [
        Fiddle::TYPE_VOIDP,
        Fiddle::TYPE_VOIDP,
        Fiddle::TYPE_LONG,
        Fiddle::TYPE_DOUBLE,
        Fiddle::TYPE_DOUBLE,
        Fiddle::TYPE_LONG,
        Fiddle::TYPE_DOUBLE,
        Fiddle::TYPE_LONG,
        Fiddle::TYPE_VOIDP,
        Fiddle::TYPE_LONG,
]
      if type == TYPES[:move]
        make = Fiddle::Function.new(objc["objc_msgSend"], head + [Fiddle::TYPE_LONG, Fiddle::TYPE_FLOAT], Fiddle::TYPE_VOIDP)
        make.call(klass("NSEvent"),
          sel("mouseEventWithType:location:modifierFlags:timestamp:windowNumber:context:eventNumber:clickCount:pressure:"),
          type, 1.0, 1.0, 0, 0.0, number, nil, 0, 0, 0.0)
      else
        make = Fiddle::Function.new(objc["objc_msgSend"], head + [Fiddle::TYPE_LONG, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
        make.call(klass("NSEvent"),
          sel("enterExitEventWithType:location:modifierFlags:timestamp:windowNumber:context:eventNumber:trackingNumber:userData:"),
          type, 1.0, 1.0, 0, 0.0, number, nil, 0, 0, nil)
      end
    end

    def self.open_menu
      items = status_items
      return false unless items.size == 1

      _, button = items.first
      Fiddle::Function.new(objc["objc_msgSend"], [Fiddle::TYPE_VOIDP] * 3, Fiddle::TYPE_VOID, need_gvl: true)
        .call(button, sel("performClick:"), nil)
      true
    end

    def self.dispatch(kinds)
      items = status_items
      return [] unless items.size == 1

      window, button = items.first
      target = find(button, "TaoTrayTarget")
      kinds.select do |kind|
        made = event(TYPES.fetch(kind), window)
        # tray-icon unwraps the event's window; one AppKit cannot find
        # would end the process, so such an event is not sent.
        next false if made.null? || msg(made, "window").null?

        msg(target, SELECTORS.fetch(kind), made)
        true
      end
    end
  end

  # tray-icon's hidden window, through user32.
  module Win32
    # tray-icon's callback message and the mouse messages it reads from
    # +lparam+ (platform_impl/windows/mod.rs:48, 286-396).
    WM_USER_TRAYICON = 6002
    MESSAGES = { enter: 0x200, click_down: 0x201, click_up: 0x202, double_click: 0x203 }.freeze

    def self.user32
      @user32 ||= Fiddle.dlopen("user32")
    end

    def self.fn(name, args, ret)
      Fiddle::Function.new(user32[name], args, ret)
    end

    # This process's windows of tray-icon's class.
    def self.tray_windows
      find = fn("FindWindowExW", [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
        Fiddle::TYPE_INTPTR_T)
      owner = fn("GetWindowThreadProcessId", [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
      class_name = "tray_icon_app\0".encode(Encoding::UTF_16LE)
      found = []
      hwnd = 0
      loop do
        hwnd = find.call(0, hwnd, class_name, nil)
        break if hwnd.zero?

        pid = Fiddle::Pointer.malloc(4, Fiddle::RUBY_FREE)
        owner.call(hwnd, pid)
        found << hwnd if pid[0, 4].unpack1("L") == Process.pid
      end
      found
    end

    WM_RBUTTONDOWN = 0x204
    WM_COMMAND = 0x111

    def self.open_menu
      windows = tray_windows
      return false unless windows.size == 1

      Fiddle::Function.new(user32["SendMessageW"],
        [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_INT, Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_INTPTR_T],
        Fiddle::TYPE_INTPTR_T, need_gvl: true).call(windows.first, WM_USER_TRAYICON, 0, WM_RBUTTONDOWN)
      true
    end

    # Chooses the item at +index+ of +hmenu+ as TrackPopupMenu does: a
    # WM_COMMAND with its id to the tray's window, which muda subclasses
    # (muda 0.17.1 platform_impl/windows/mod.rs:378-386, 973-981). Any thread may post it.
    def self.choose(hmenu, index)
      id = fn("GetMenuItemID", [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_INT], Fiddle::TYPE_INT).call(hmenu, index)
      fn("PostMessageW", [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_INT, Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_INTPTR_T],
        Fiddle::TYPE_INT).call(tray_windows.first, WM_COMMAND, id, 0)
    end

    def self.dispatch(kinds)
      windows = tray_windows
      return [] unless windows.size == 1

      send = fn("SendMessageW", [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_INT, Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_INTPTR_T],
        Fiddle::TYPE_INTPTR_T)
      kinds.each { |kind| send.call(windows.first, WM_USER_TRAYICON, 0, MESSAGES.fetch(kind)) }
      kinds
    end
  end
end
