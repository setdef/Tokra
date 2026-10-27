# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019 Osspial
# SPDX-SnippetComment: Handle types and HandleError adapted from
#                      raw-window-handle 0.6.2 (src/lib.rs, src/windows.rs,
#                      src/appkit.rs, src/unix.rs), which is MIT OR
#                      Apache-2.0 OR Zlib; taken here under MIT OR Apache-2.0

module Tokra
  # The native names of a window and its display, as plain values.
  #
  # Every desktop has its own way to name a window: Windows hands out an
  # +HWND+, macOS an +NSView+, X11 a window ID, and Wayland a surface. A
  # library that draws into your window, or opens a dialog in front of it,
  # needs that name. Rust's raw-window-handle crate gives each kind a type,
  # and Tauri's windows answer with one (ADR 013).
  #
  # Window#window_handle answers with one of these window handles, and
  # Window#display_handle and AppHandle#display_handle with one of these
  # display handles. Each field is an Integer. A pointer, such as
  # AppKitWindowHandle#ns_view, is its address.
  #
  # Reading a handle is always safe. Using one is not: nothing stops the
  # window from closing while you hold its handle, and an address turned
  # back into a pointer after that, or on a thread other than the main
  # thread, can crash your process. Use a handle only on the main thread,
  # while the window is open, and only with a library that says it takes
  # one.
  #
  # Mirrors the raw-window-handle 0.6.2 types tao 0.34.5 answers with for a
  # desktop window (raw-window-handle <tt>src/windows.rs</tt>,
  # <tt>src/appkit.rs</tt>, <tt>src/unix.rs</tt>). The crate's
  # <tt>RawWindowHandle</tt> and <tt>RawDisplayHandle</tt> enums wrap one of
  # these per variant; here the value is the variant.
  #
  # === Examples
  #
  #   case window.window_handle
  #   in Tokra::RawWindowHandle::Win32WindowHandle(hwnd:) then puts "HWND #{hwnd}"
  #   in Tokra::RawWindowHandle::XlibWindowHandle(window:) then puts "X11 window #{window}"
  #   in handle then puts handle.inspect
  #   end
  #
  #   begin
  #     window.window_handle
  #   rescue Tokra::RawWindowHandle::HandleError => e
  #     warn e.message # the underlying handle is not available
  #   end
  module RawWindowHandle
    # A Win32 window, by its +HWND+ and, when known, the +HINSTANCE+ of the
    # module that created it (raw-window-handle <tt>src/windows.rs:52-57</tt>).
    #
    # === Example
    #
    #   Win32WindowHandle.new(hwnd: 0x40A2C, hinstance: nil)
    class Win32WindowHandle < Data.define(:hwnd, :hinstance)
      ##
      # :attr_reader: hwnd
      # The window's +HWND+, a non-zero Integer.

      ##
      # :attr_reader: hinstance
      # The +HINSTANCE+ of the module that created the window, a non-zero
      # Integer, or +nil+.
    end

    # The Windows display. Windows has one, so this value carries nothing
    # (raw-window-handle <tt>src/windows.rs:12</tt>).
    #
    # === Example
    #
    #   WindowsDisplayHandle.new
    class WindowsDisplayHandle < Data.define
    end

    # An AppKit window, by the address of its content +NSView+
    # (raw-window-handle <tt>src/appkit.rs:88-91</tt>).
    #
    # === Example
    #
    #   AppKitWindowHandle.new(ns_view: 0x6000_0123_4560)
    class AppKitWindowHandle < Data.define(:ns_view)
      ##
      # :attr_reader: ns_view
      # The address of the window's +NSView+, a non-zero Integer.
    end

    # The AppKit display. macOS has one, so this value carries nothing
    # (raw-window-handle <tt>src/appkit.rs:9</tt>).
    #
    # === Example
    #
    #   AppKitDisplayHandle.new
    class AppKitDisplayHandle < Data.define
    end

    # An X11 window, through Xlib, by its window ID and visual ID
    # (raw-window-handle <tt>src/unix.rs:48-53</tt>).
    #
    # === Example
    #
    #   XlibWindowHandle.new(window: 0x3A0_0007, visual_id: 0)
    class XlibWindowHandle < Data.define(:window, :visual_id)
      ##
      # :attr_reader: window
      # The window's X11 ID, an Integer.

      ##
      # :attr_reader: visual_id
      # The window's X11 visual ID, an Integer; 0 when unknown.
    end

    # An X11 display, through Xlib (raw-window-handle
    # <tt>src/unix.rs:8-21</tt>).
    #
    # === Example
    #
    #   XlibDisplayHandle.new(display: 0x5555_0000_1000, screen: 0)
    class XlibDisplayHandle < Data.define(:display, :screen)
      ##
      # :attr_reader: display
      # The address of Xlib's +Display+, a non-zero Integer, or +nil+.

      ##
      # :attr_reader: screen
      # The X11 screen number, an Integer.
    end

    # A Wayland window, by the address of its +wl_surface+
    # (raw-window-handle <tt>src/unix.rs:184-187</tt>).
    #
    # === Example
    #
    #   WaylandWindowHandle.new(surface: 0x5555_0000_2000)
    class WaylandWindowHandle < Data.define(:surface)
      ##
      # :attr_reader: surface
      # The address of the window's +wl_surface+, a non-zero Integer.
    end

    # A Wayland display, by the address of its +wl_display+
    # (raw-window-handle <tt>src/unix.rs:156-159</tt>).
    #
    # === Example
    #
    #   WaylandDisplayHandle.new(display: 0x5555_0000_3000)
    class WaylandDisplayHandle < Data.define(:display)
      ##
      # :attr_reader: display
      # The address of the +wl_display+, a non-zero Integer.
    end

    # Raised when a window or display cannot answer with a handle.
    #
    # Mirrors raw-window-handle's <tt>HandleError</tt> (src/lib.rs:346-388):
    # each variant is a subclass, and the message is the crate's Display
    # text.
    #
    # === Example
    #
    #   rescue Tokra::RawWindowHandle::HandleError::Unavailable
    class HandleError < StandardError
      # The underlying handle cannot be represented using the types in
      # this crate (src/lib.rs:350-364): the window system has no handle
      # kind this module defines.
      class NotSupported < HandleError
        # The crate's Display text.
        MESSAGE = "the underlying handle cannot be represented using the types in this crate"

        # Creates the error with the crate's message.
        def initialize(message = MESSAGE)
          super
        end
      end

      # The underlying handle is not available (src/lib.rs:366-375). Tokra
      # raises it for a window whose event loop has ended, as Tauri does
      # for a closed window, and before the app has a window at all.
      class Unavailable < HandleError
        # The crate's Display text.
        MESSAGE = "the underlying handle is not available"

        # Creates the error with the crate's message.
        def initialize(message = MESSAGE)
          super
        end
      end
    end

    # The window handle for the tagged Array a Native::Window answers
    # +raw_window_handle+ with, raising the HandleError it names.
    def self.window_handle(native) # :nodoc:
      case native
      in [:Win32, Integer => hwnd, (Integer | nil) => hinstance] then Win32WindowHandle.new(hwnd:, hinstance:)
      in [:AppKit, Integer => ns_view] then AppKitWindowHandle.new(ns_view:)
      in [:Xlib, Integer => window, Integer => visual_id] then XlibWindowHandle.new(window:, visual_id:)
      in [:Wayland, Integer => surface] then WaylandWindowHandle.new(surface:)
      in [:Unavailable] then raise HandleError::Unavailable
      else raise HandleError::NotSupported
      end
    end

    # The display handle for the tagged Array a Native::Window answers
    # +raw_display_handle+ with, raising the HandleError it names.
    def self.display_handle(native) # :nodoc:
      case native
      in [:Windows] then WindowsDisplayHandle.new
      in [:AppKit] then AppKitDisplayHandle.new
      in [:Xlib, (Integer | nil) => display, Integer => screen] then XlibDisplayHandle.new(display:, screen:)
      in [:Wayland, Integer => display] then WaylandDisplayHandle.new(display:)
      in [:Unavailable] then raise HandleError::Unavailable
      else raise HandleError::NotSupported
      end
    end
  end
end

# SPDX-SnippetEnd
