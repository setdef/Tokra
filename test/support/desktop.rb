# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "rbconfig"

# What the desktop a real-window test runs on lacks, for the tests that
# need it (Plan 061).
#
# Windows can give a program a desktop of its own, as a build machine or a
# service does, so its windows open on no one's screen. Windows, webviews,
# menus, and focus all work there. Two things a few tests need do not: the
# notification area, which belongs to Explorer's taskbar on the desktop a
# person signs in to, so a tray icon has nowhere to go; and the cursor,
# which only the desktop that takes the mouse has.
#
# A Mac can run a program outside any login session, as a build machine's
# daemon does. There is no window server there, so no window opens, and
# neither does the pasteboard, a file panel, or the notification center.
#
# Each method probes for exactly that, once, and only on its own system,
# so a Windows machine with a taskbar and a cursor and a Mac with a GUI
# session, such as CI's runners, skip nothing. Use it as
# RealApp.unavailable_reason is used:
#
#   reason = Desktop.tray_unavailable_reason
#   skip reason if reason
module Desktop
  # Why this Mac has no GUI session, or +nil+ when it has one or this is
  # not a Mac. launchd names the session a process runs in: Aqua for a
  # person's login, System for a daemon's.
  def self.session_unavailable_reason
    return nil unless macos?
    return @session if defined?(@session)

    @session = no_session_reason(IO.popen(["launchctl", "managername"], err: File::NULL, &:read).to_s.strip)
  end

  # Why launchd's session +name+ is not a GUI session, or +nil+ for Aqua.
  def self.no_session_reason(name)
    "no macOS GUI session (launchctl managername is #{name.inspect}, not \"Aqua\")" unless name == "Aqua"
  end

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

  # Runs the block with a window of this process shown on the desktop, on
  # Windows, and answers what the block answers. Elsewhere it only runs
  # the block.
  #
  # A desktop a person signs in to always shows other programs' windows,
  # Explorer's among them. A desktop made for one test run shows only what
  # the run opens, and there Windows ignores a webview window's requests
  # to change its place in the z-order while no other process shows a
  # window: SetWindowPos with HWND_TOPMOST answers success, and the window
  # never gains WS_EX_TOPMOST. A window with no webview is not affected,
  # nor is a webview's window once another process shows any window,
  # however idle. So a test that reads where Windows put a fixture's
  # window launches it beside this one, as it would be beside the shell's,
  # and does not depend on whether an earlier test left a window open.
  def self.beside_a_window(&)
    windows? ? Win32.beside_a_window(&) : yield
  end

  def self.windows?
    RbConfig::CONFIG["host_os"].match?(/mswin|mingw|cygwin/)
  end

  def self.macos?
    RbConfig::CONFIG["host_os"].include?("darwin")
  end

  # The user32 calls, by windows-sys 0.59.0's signatures
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

    # WS_OVERLAPPEDWINDOW | WS_VISIBLE.
    SHOWN = 0x10CF0000

    # Shows a plain STATIC window on a thread of its own, which answers the
    # window's messages, while the block runs, and closes it after.
    def self.beside_a_window
      user32 # loads Fiddle, whose types the calls below name
      opened = Thread::Queue.new
      done = false
      thread = Thread.new do
        window = 0
        begin
          window = shown_window
        ensure
          opened << [window, Fiddle.win32_last_error]
        end
        pump until done
      ensure
        fn("DestroyWindow", [Fiddle::TYPE_INTPTR_T], Fiddle::TYPE_INT).call(window) if window.nonzero?
      end
      window, error = opened.pop
      raise "CreateWindowExW made no window (error #{error})" if window.zero?

      yield
    ensure
      done = true
      thread&.join
    end

    def self.shown_window
      # The extended style, class, title, style, x, y, width, height,
      # parent, menu, instance, and parameter.
      args = [Fiddle::TYPE_UINT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT] +
        ([Fiddle::TYPE_INT] * 4) + ([Fiddle::TYPE_INTPTR_T] * 3) + [Fiddle::TYPE_VOIDP]
      create = fn("CreateWindowExW", args, Fiddle::TYPE_INTPTR_T)
      create.call(0, "STATIC\0".encode(Encoding::UTF_16LE), "Tokra test: another window\0".encode(Encoding::UTF_16LE),
        SHOWN, 0, 0, 240, 120, 0, 0, 0, nil)
    end

    # Dispatches the messages waiting for this thread's windows, then
    # sleeps a moment.
    def self.pump
      # The message, window, first and last message, and whether to
      # remove it.
      @peek ||= fn("PeekMessageW", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INTPTR_T] + ([Fiddle::TYPE_UINT] * 3), Fiddle::TYPE_INT)
      @dispatch ||= fn("DispatchMessageW", [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INTPTR_T)
      message = Fiddle::Pointer.malloc(48, Fiddle::RUBY_FREE)
      @dispatch.call(message) while @peek.call(message, 0, 0, 0, 1).nonzero?
      sleep 0.02
    end
  end
end
