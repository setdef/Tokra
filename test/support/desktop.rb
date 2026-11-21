# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "rbconfig"

# What the desktop a real-window test runs on lacks, for the few tests
# that need it (Plan 061).
#
# Windows can give a program a desktop of its own, as a build machine or a
# service does, so its windows open on no one's screen. Windows, webviews,
# menus, and focus all work there. Two things a few tests need do not: the
# notification area, which belongs to Explorer's taskbar on the desktop a
# person signs in to, so a tray icon has nowhere to go; and the cursor,
# which only the desktop that takes the mouse has.
#
# Each method probes for exactly that, once, and only on Windows, so a
# Windows machine with a taskbar and a cursor, such as CI's runner, skips
# nothing. Use it as RealApp.unavailable_reason is used:
#
#   reason = Desktop.tray_unavailable_reason
#   skip reason if reason
module Desktop
  # Why no tray icon can show on this desktop, or +nil+ when one can.
  def self.tray_unavailable_reason
    return nil unless windows?
    return @tray if defined?(@tray)

    @tray = ("this desktop has no notification area for tray icons (Windows finds no taskbar here)" if Win32.taskbar.zero?)
  end

  # Why this desktop has no cursor position to read, or +nil+ when it has.
  def self.cursor_unavailable_reason
    return nil unless windows?
    return @cursor if defined?(@cursor)

    error = Win32.cursor_error
    @cursor = ("this desktop has no cursor to read (GetCursorPos fails with error #{error})" if error)
  end

  def self.windows?
    RbConfig::CONFIG["host_os"].match?(/mswin|mingw|cygwin/)
  end

  # The two user32 calls, by windows-sys 0.59.0's signatures
  # (Win32/UI/WindowsAndMessaging/mod.rs).
  module Win32
    def self.user32
      require "fiddle"
      @user32 ||= Fiddle.dlopen("user32")
    end

    def self.fn(name, args, ret)
      Fiddle::Function.new(user32[name], args, ret)
    end

    # The taskbar's window, whose class is Shell_TrayWnd, or 0 when this
    # desktop has none.
    def self.taskbar
      find = fn("FindWindowW", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INTPTR_T)
      find.call("Shell_TrayWnd\0".encode(Encoding::UTF_16LE), nil)
    end

    # GetCursorPos's error, or +nil+ when it reads the cursor.
    def self.cursor_error
      point = Fiddle::Pointer.malloc(8, Fiddle::RUBY_FREE)
      read = fn("GetCursorPos", [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT).call(point)
      read.zero? ? Fiddle.win32_last_error : nil
    end
  end
end
