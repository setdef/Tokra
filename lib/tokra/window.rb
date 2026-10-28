# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Window structure adapted from tauri/crates/tauri/src/window/mod.rs

module Tokra
  # Window wrapper holding native window reference and ResourceTable.
  #
  # Mirrors Tauri's Window<R> struct. Each window owns its own
  # resources_table, used as fallback if webview table doesn't have resource.
  class Window
    include Manager

    # The unique label identifying this window.
    attr_reader :label

    # The app handle for accessing shared state.
    attr_reader :app_handle

    # The native tao/winit Window handle.
    attr_reader :native

    # Creates a new Window wrapper.
    #
    # +label+:: a unique identifier for this window (e.g., "main").
    # +native+:: the Native::Window handle from tao/winit.
    # +app_handle+:: provides access to app-level state and config.
    # +menu+:: the WindowMenu it opens with, or +nil+.
    def initialize(label:, native:, app_handle:, menu: nil)
      @label = label
      @native = native
      @app_handle = app_handle
      @resources_table = ResourceTable.new
      @menu_mutex = Thread::Mutex.new
      @window_menu = menu
    end

    # SPDX-SnippetBegin
    # SPDX-License-Identifier: Apache-2.0 OR MIT
    # SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    # SPDX-SnippetComment: Window menus adapted from tauri/crates/tauri/src/window/mod.rs

    # The menu a window shows, and whether it is the app's (plan 042).
    #
    # Mirrors Tauri's WindowMenu (window/mod.rs:907-914).
    WindowMenu = Data.define(:is_app_wide, :menu) # :nodoc:

    # Calls the block with this window and each Menu::MenuEvent, a click
    # on any menu item, and returns +nil+.
    #
    # The block hears every click, whether on this window's menu, the
    # app's, or another window's. A window has one such block; a second
    # call replaces the first.
    #
    # Mirrors Tauri's Window::on_menu_event (window/mod.rs:1152-1163).
    #
    # === Example
    #
    #   window.on_menu_event { |window, event| window.close if event.id == "close" }
    def on_menu_event(&handler)
      @app_handle.menu_manager.set_window_listener(@label, handler)
    end

    # The menu this window shows, or +nil+.
    #
    # On Windows and Linux a window opens with the app's menu, if the app
    # has one. On macOS menus belong to the app, so a window's menu is
    # only what #set_menu gave it.
    #
    # Mirrors Tauri's Window::menu (window/mod.rs:1188-1191).
    def menu
      window_menu&.menu
    end

    # Gives this window +menu+ and returns the menu it had, or +nil+.
    #
    # On Windows and Linux the menu bar shows inside the window. On macOS
    # this only records the menu: macOS shows the app's menu, which
    # AppHandle#set_menu sets. The native work runs on the main thread;
    # from another thread it travels there.
    #
    # Mirrors Tauri's Window::set_menu (window/mod.rs:1199-1242).
    #
    # === Example
    #
    #   window.set_menu(Tokra::Menu::MenuBuilder.new(window).text("reload", "Reload").build)
    def set_menu(menu)
      previous = remove_menu
      @app_handle.menu_manager.insert_menu_into_stash(menu)
      native = @native
      native_menu = menu.native #: Native::Menu
      # +nil+: the window's own theme, as Tauri's set_menu reads it.
      dispatch { native.init_menu(native_menu, nil) } if native.respond_to?(:init_menu)
      replace_window_menu(WindowMenu.new(is_app_wide: false, menu:))
      previous
    end

    # Takes this window's menu away and returns it, or +nil+.
    #
    # Mirrors Tauri's Window::remove_menu (window/mod.rs:1244-1276).
    def remove_menu
      previous = replace_window_menu(nil)&.menu
      native = @native
      if previous && native.respond_to?(:remove_menu)
        native_menu = previous.native #: Native::Menu
        dispatch { native.remove_menu(native_menu) }
      end
      @app_handle.__send__(:remove_menu_from_stash_by_id, previous&.id)
      previous
    end

    # Hides this window's menu bar and returns +nil+. Windows and Linux;
    # on macOS it does nothing.
    #
    # Mirrors Tauri's Window::hide_menu (window/mod.rs:1278-1304).
    def hide_menu
      current = window_menu
      native = @native
      return nil unless current && native.respond_to?(:hide_menu)

      native_menu = current.menu.native #: Native::Menu
      dispatch { native.hide_menu(native_menu) }
    end

    # Shows this window's menu bar again and returns +nil+. Windows and
    # Linux; on macOS it does nothing.
    #
    # Mirrors Tauri's Window::show_menu (window/mod.rs:1306-1332).
    def show_menu
      current = window_menu
      native = @native
      return nil unless current && native.respond_to?(:show_menu)

      native_menu = current.menu.native #: Native::Menu
      dispatch { native.show_menu(native_menu) }
    end

    # Whether this window shows its menu bar: +false+ with no menu, on
    # macOS, or when the window has closed.
    #
    # Mirrors Tauri's Window::is_menu_visible (window/mod.rs:1334-1363),
    # whose unanswered query answers +false+.
    def is_menu_visible
      current = window_menu
      native = @native
      return false unless current && native.respond_to?(:is_menu_visible)

      native_menu = current.menu.native #: Native::Menu
      @app_handle.runtime_context.run_main_thread { native.is_menu_visible(native_menu) }
    rescue Error::FailedToReceiveMessage
      false
    end

    # Shows +menu+, a Menu or a Submenu, as a context menu on this window
    # at the pointer, and returns +nil+ once it closes, as
    # ContextMenu#popup does.
    #
    # Mirrors Tauri's Window::popup_menu (window/mod.rs:1365-1368).
    #
    # === Example
    #
    #   window.popup_menu(Tokra::Menu::Menu.with_items(window, [
    #     Tokra::Menu::MenuItem.with_id(window, "inspect", "Inspect", true, nil),
    #   ]))
    def popup_menu(menu)
      case menu
      when Menu::ContextMenu then menu.popup(self)
      else raise TypeError, "wrong argument type #{menu.class} (expected Tokra::Menu::ContextMenu)"
      end
    end

    # Shows +menu+, a Menu or a Submenu, as a context menu on this window
    # at +position+, a LogicalPosition or a PhysicalPosition relative to
    # the window's top-left corner, and returns +nil+ once it closes, as
    # ContextMenu#popup_at does.
    #
    # Mirrors Tauri's Window::popup_menu_at (window/mod.rs:1370-1379).
    #
    # === Example
    #
    #   window.popup_menu_at(menu, Tokra::LogicalPosition.new(x: 40, y: 60))
    def popup_menu_at(menu, position)
      case menu
      when Menu::ContextMenu then menu.popup_at(self, position)
      else raise TypeError, "wrong argument type #{menu.class} (expected Tokra::Menu::ContextMenu)"
      end
    end

    # Whether this window shows the app's menu.
    def has_app_wide_menu? # :nodoc:
      window_menu&.is_app_wide || false
    end

    # Whether this window's menu has the id +id+.
    def menu_in_use?(id) # :nodoc:
      current = window_menu
      !current.nil? && current.menu.id == id
    end

    # Sets the WindowMenu and returns the one before it.
    def replace_window_menu(window_menu) # :nodoc:
      @menu_mutex.synchronize do
        previous = @window_menu
        @window_menu = window_menu
        previous
      end
    end

    private def window_menu
      @menu_mutex.synchronize { @window_menu }
    end

    # SPDX-SnippetEnd

    # Per-window resource table.
    def resources_table
      @resources_table
    end

    # Sets the window title and returns +nil+.
    #
    # From another thread the change travels to the main thread and this
    # method returns without waiting for it, as Tauri's set_title does
    # (window/mod.rs, tauri-runtime-wry lib.rs:2093-2098). Raises
    # Error::Runtime when the event loop has ended.
    #
    # === Example
    #
    #   window.set_title("Saved")
    def set_title(title)
      native = @native
      dispatch { native.set_title(title) }
    end

    # Keeps the window above every other window, or lets it go back
    # among them, and returns +nil+.
    #
    # A palette, a timer, or a video you watch while you work stays in
    # sight when another app comes to the front. On macOS the window
    # floats above other apps' windows without taking the keyboard from
    # them. On Linux the window manager may ignore the request, and on
    # Wayland it does nothing.
    #
    # From another thread the change travels to the main thread and this
    # method returns without waiting for it, as Tauri's
    # Window::set_always_on_top does (window/mod.rs:1866-1873,
    # tauri-runtime-wry lib.rs:2184-2189, 3390). Raises Error::Runtime when
    # the event loop has ended.
    #
    # === Example
    #
    #   window.set_always_on_top(true)
    def set_always_on_top(always_on_top)
      native = @native
      dispatch { native.set_always_on_top(always_on_top) }
    end

    # Lets the cursor's clicks and moves pass through the window to
    # whatever is behind it, or catches them again, and returns +nil+.
    #
    # An overlay that shows something over your work, such as a heads-up
    # display or a floating clock, should not swallow the clicks meant for
    # the app underneath. Pass +true+ and the window ignores the cursor;
    # pass +false+ to catch its events again, as every window does at
    # first.
    #
    # From another thread the change travels to the main thread and this
    # method returns without waiting for it, as Tauri's
    # Window::set_ignore_cursor_events does (window/mod.rs:2087-2094,
    # tauri-runtime-wry lib.rs:2326-2331, 3461-3463). Raises Error::Runtime
    # when the event loop has ended.
    #
    # === Example
    #
    #   window.set_ignore_cursor_events(true)
    def set_ignore_cursor_events(ignore)
      native = @native
      dispatch { native.set_ignore_cursor_events(ignore) }
    end

    # The window title.
    #
    # From another thread this asks the main thread and waits for its
    # answer. Raises Error::Runtime when the event loop has ended, or ends
    # before it answers.
    #
    # Mirrors Tauri's Window::title (window/mod.rs:1493-1495), a getter
    # the runtime answers on the main thread (tauri-runtime-wry
    # lib.rs:1942-1944, 3293).
    #
    # === Example
    #
    #   window.title  #=> "Tokra"
    def title
      native = @native
      getter { native.title }
    end

    # The number of physical pixels in one of the window's logical pixels:
    # 2.0 on most Retina displays, 1.0 on most others.
    #
    # Getters such as this one answer on the main thread; from another
    # thread they ask it and wait. Each raises Error::Runtime "failed to
    # receive message from webview" for a closed window, whose getter
    # Tauri's runtime leaves unanswered (tauri-runtime-wry lib.rs:3244-3250),
    # and Error::Runtime when the event loop has ended.
    #
    # Mirrors Tauri's Window::scale_factor (window/mod.rs:1384), which asks
    # tao (lib.rs:3260).
    #
    # === Example
    #
    #   window.scale_factor  #=> 2.0
    def scale_factor
      native = @native
      getter { native.scale_factor }
    end

    # The top-left corner of the window's client area, inside its frame,
    # relative to the desktop: a PhysicalPosition. Answers as #scale_factor
    # does, and raises Error::Runtime "failed to send message to the
    # webview" where the platform cannot tell (Wayland), as Tauri does.
    #
    # Mirrors Tauri's Window::inner_position (window/mod.rs:1389;
    # lib.rs:3261-3268).
    #
    # === Example
    #
    #   window.inner_position  #=> #<data Tokra::PhysicalPosition x=200, y=150>
    def inner_position
      native = @native
      physical_position(getter { native.inner_position })
    end

    # The top-left corner of the window's frame, title bar included,
    # relative to the desktop: a PhysicalPosition. Answers as
    # #inner_position does.
    #
    # Mirrors Tauri's Window::outer_position (window/mod.rs:1394;
    # lib.rs:3269-3276).
    #
    # === Example
    #
    #   window.outer_position  #=> #<data Tokra::PhysicalPosition x=200, y=122>
    def outer_position
      native = @native
      physical_position(getter { native.outer_position })
    end

    # The size of the window's client area, inside its frame: a
    # PhysicalSize. Answers as #scale_factor does.
    #
    # On macOS this is the size of the window's webview, as in Tauri,
    # because the webview replaces the view tao would measure.
    #
    # Mirrors Tauri's Window::inner_size (window/mod.rs:1401;
    # lib.rs:3277-3279, 5195-5222).
    #
    # === Example
    #
    #   window.inner_size  #=> #<data Tokra::PhysicalSize width=1600, height=1200>
    def inner_size
      native = @native
      webview = webviews.each_value.find { |candidate| candidate.window.equal?(self) }&.native
      width, height = getter { native.inner_size(webview) }
      PhysicalSize.new(width:, height:)
    end

    # The size of the whole window, its frame and title bar included: a
    # PhysicalSize. Answers as #scale_factor does.
    #
    # Mirrors Tauri's Window::outer_size (window/mod.rs:1408;
    # lib.rs:3280-3282).
    #
    # === Example
    #
    #   window.outer_size  #=> #<data Tokra::PhysicalSize width=1600, height=1256>
    def outer_size
      native = @native
      width, height = getter { native.outer_size }
      PhysicalSize.new(width:, height:)
    end

    # Whether the window fills the screen. Answers as #scale_factor does.
    #
    # Mirrors Tauri's Window::is_fullscreen (window/mod.rs:1413;
    # lib.rs:3283).
    #
    # === Example
    #
    #   window.is_fullscreen  #=> false
    def is_fullscreen
      native = @native
      getter { native.is_fullscreen }
    end

    # Whether the window is minimized. Answers as #scale_factor does.
    #
    # Mirrors Tauri's Window::is_minimized (window/mod.rs:1418;
    # lib.rs:3284).
    #
    # === Example
    #
    #   window.is_minimized  #=> false
    def is_minimized
      native = @native
      getter { native.is_minimized }
    end

    # Whether the window is maximized. Answers as #scale_factor does.
    #
    # Mirrors Tauri's Window::is_maximized (window/mod.rs:1423;
    # lib.rs:3285).
    #
    # === Example
    #
    #   window.is_maximized  #=> false
    def is_maximized
      native = @native
      getter { native.is_maximized }
    end

    # Whether the window has the keyboard. Answers as #scale_factor does.
    #
    # Mirrors Tauri's Window::is_focused (window/mod.rs:1428;
    # lib.rs:3286).
    #
    # === Example
    #
    #   window.is_focused  #=> true
    def is_focused
      native = @native
      getter { native.is_focused }
    end

    # Whether the window has a frame and title bar. Answers as
    # #scale_factor does.
    #
    # Mirrors Tauri's Window::is_decorated (window/mod.rs:1433;
    # lib.rs:3287).
    #
    # === Example
    #
    #   window.is_decorated  #=> true
    def is_decorated
      native = @native
      getter { native.is_decorated }
    end

    # Whether a person can resize the window. Answers as #scale_factor
    # does.
    #
    # Mirrors Tauri's Window::is_resizable (window/mod.rs:1438;
    # lib.rs:3288).
    #
    # === Example
    #
    #   window.is_resizable  #=> true
    def is_resizable
      native = @native
      getter { native.is_resizable }
    end

    # Whether the window stays above other windows, as
    # #set_always_on_top asks. Answers as #scale_factor does.
    #
    # Mirrors Tauri's Window::is_always_on_top (window/mod.rs:1452;
    # lib.rs:3331).
    #
    # === Example
    #
    #   window.is_always_on_top  #=> false
    def is_always_on_top
      native = @native
      getter { native.is_always_on_top }
    end

    # Whether the window's maximize button is enabled. Answers as
    # #scale_factor does.
    #
    # Mirrors Tauri's Window::is_maximizable (window/mod.rs:1465;
    # lib.rs:3289).
    #
    # === Example
    #
    #   window.is_maximizable  #=> true
    def is_maximizable
      native = @native
      getter { native.is_maximizable }
    end

    # Whether the window's minimize button is enabled. Answers as
    # #scale_factor does.
    #
    # Mirrors Tauri's Window::is_minimizable (window/mod.rs:1474;
    # lib.rs:3290).
    #
    # === Example
    #
    #   window.is_minimizable  #=> true
    def is_minimizable
      native = @native
      getter { native.is_minimizable }
    end

    # Whether the window's close button is enabled. Answers as
    # #scale_factor does.
    #
    # Mirrors Tauri's Window::is_closable (window/mod.rs:1483;
    # lib.rs:3291).
    #
    # === Example
    #
    #   window.is_closable  #=> true
    def is_closable
      native = @native
      getter { native.is_closable }
    end

    # Whether the window is shown. Answers as #scale_factor does.
    #
    # Mirrors Tauri's Window::is_visible (window/mod.rs:1488;
    # lib.rs:3292).
    #
    # === Example
    #
    #   window.is_visible  #=> true
    def is_visible
      native = @native
      getter { native.is_visible }
    end

    # The monitor the window is on, as a Monitor, or +nil+ when the
    # platform cannot tell. Answers as #scale_factor does.
    #
    # Mirrors Tauri's Window::current_monitor (window/mod.rs:1500;
    # lib.rs:3294).
    #
    # === Example
    #
    #   window.current_monitor.name  #=> "Built-in Retina Display"
    def current_monitor
      native = @native
      maybe_monitor(getter { native.current_monitor })
    end

    # The monitor that holds the point (+x+, +y+), in physical pixels of
    # the desktop, as a Monitor, or +nil+ when none does. Answers as
    # #scale_factor does, except that once the event loop has ended it
    # raises "failed to receive message from webview", as Tauri's does.
    #
    # Mirrors Tauri's Window::monitor_from_point (window/mod.rs:1510;
    # lib.rs:3296-3298).
    #
    # === Example
    #
    #   window.monitor_from_point(10.0, 10.0).position  #=> #<data Tokra::PhysicalPosition x=0, y=0>
    def monitor_from_point(x, y)
      native = @native
      x = Float(x)
      y = Float(y)
      maybe_monitor(getter { native.monitor_from_point(x, y) })
    rescue Error::Runtime => e
      # Tauri's dispatcher ignores a failed send here and fails on the
      # channel instead (lib.rs:1954-1967).
      raise unless e.message.end_with?(Error::Runtime::FAILED_TO_SEND_MESSAGE)

      raise Error::Runtime, Error::Runtime::FAILED_TO_RECEIVE_MESSAGE
    end

    # The system's main monitor, as a Monitor, or +nil+ when the platform
    # cannot tell (Wayland). Answers as #scale_factor does.
    #
    # Mirrors Tauri's Window::primary_monitor (window/mod.rs:1522;
    # lib.rs:3295).
    #
    # === Example
    #
    #   window.primary_monitor.size  #=> #<data Tokra::PhysicalSize width=3024, height=1964>
    def primary_monitor
      native = @native
      maybe_monitor(getter { native.primary_monitor })
    end

    # Every monitor attached to the computer, as an Array of Monitors.
    # Answers as #scale_factor does.
    #
    # Mirrors Tauri's Window::available_monitors (window/mod.rs:1532;
    # lib.rs:3299-3301).
    #
    # === Example
    #
    #   window.available_monitors.size  #=> 2
    def available_monitors
      native = @native
      getter { native.available_monitors }.map { |entry| Monitor.from_native(entry) }
    end

    # The window's appearance, Theme::Light or Theme::Dark. A theme Tauri
    # does not know reads as Light, as in Tauri. Answers as #scale_factor
    # does.
    #
    # Mirrors Tauri's Window::theme (window/mod.rs:1627), mapped as
    # map_theme maps tao's (lib.rs:578-584, 3327-3329).
    #
    # === Example
    #
    #   window.theme  #=> #<data Tokra::Theme name="Dark">
    def theme
      native = @native
      Theme.const_get(getter { native.theme }, false)
    end

    # Moves the window to the middle of its monitor's work area and
    # returns +nil+.
    #
    # Setters such as this one run on the main thread; from another thread
    # the call travels there and the method returns without waiting for
    # it. A closed window ignores it. Each raises Error::Runtime when the
    # event loop has ended.
    #
    # On macOS AppKit centers it, a little above the middle as AppKit
    # prefers; elsewhere the window's outer size is centered in
    # Monitor#work_area.
    #
    # Mirrors Tauri's Window::center (window/mod.rs:1652; lib.rs:3333),
    # which tauri-runtime-wry's WindowExt implements for each platform
    # (window/macos.rs, linux.rs, windows.rs).
    #
    # === Example
    #
    #   window.center
    def center
      native = @native
      dispatch { native.center }
    end

    # Asks for the person's attention and returns +nil+: on macOS the Dock
    # icon bounces, and on Windows the taskbar button flashes, as
    # UserAttentionType describes. +nil+ cancels a request. Nothing happens
    # while the app is in front. Runs as #center does.
    #
    # Mirrors Tauri's Window::request_user_attention (window/mod.rs:1667;
    # lib.rs:3334-3336).
    #
    # === Example
    #
    #   window.request_user_attention(Tokra::UserAttentionType::Critical)
    def request_user_attention(request_type)
      native = @native
      expect(request_type, UserAttentionType) if request_type
      name = request_type&.name
      dispatch { native.request_user_attention(name) }
    end

    # Lets a person resize the window, or stops them, and returns +nil+.
    # Runs as #center does.
    #
    # On Windows a resizable window without decorations can still be
    # resized by its edges: Tauri covers it with a window that answers as
    # its frame, and this attaches or removes that cover (plan 041,
    # decision 5).
    #
    # Mirrors Tauri's Window::set_resizable (window/mod.rs:1680;
    # lib.rs:3337-3348; undecorated_resizing.rs:117-196, 403-411).
    #
    # === Example
    #
    #   window.set_resizable(false)
    def set_resizable(resizable)
      native = @native
      dispatch { native.set_resizable(resizable) }
    end

    # Enables or disables the window's maximize button and returns +nil+.
    # Runs as #center does. On macOS it also enables or disables the
    # fullscreen button.
    #
    # Mirrors Tauri's Window::set_maximizable (window/mod.rs:1695;
    # lib.rs:3349).
    #
    # === Example
    #
    #   window.set_maximizable(false)
    def set_maximizable(maximizable)
      native = @native
      dispatch { native.set_maximizable(maximizable) }
    end

    # Enables or disables the window's minimize button and returns +nil+.
    # Runs as #center does.
    #
    # Mirrors Tauri's Window::set_minimizable (window/mod.rs:1708;
    # lib.rs:3350).
    #
    # === Example
    #
    #   window.set_minimizable(false)
    def set_minimizable(minimizable)
      native = @native
      dispatch { native.set_minimizable(minimizable) }
    end

    # Enables or disables the window's close button and returns +nil+.
    # Runs as #center does.
    #
    # Mirrors Tauri's Window::set_closable (window/mod.rs:1723;
    # lib.rs:3351).
    #
    # === Example
    #
    #   window.set_closable(false)
    def set_closable(closable)
      native = @native
      dispatch { native.set_closable(closable) }
    end

    # Maximizes the window and returns +nil+. Runs as #center does.
    #
    # Mirrors Tauri's Window::maximize (window/mod.rs:1750; lib.rs:3353).
    #
    # === Example
    #
    #   window.maximize
    def maximize
      native = @native
      dispatch { native.set_maximized(true) }
    end

    # Restores a maximized window to its size before and returns +nil+.
    # Runs as #center does.
    #
    # Mirrors Tauri's Window::unmaximize (window/mod.rs:1755;
    # lib.rs:3354).
    #
    # === Example
    #
    #   window.unmaximize
    def unmaximize
      native = @native
      dispatch { native.set_maximized(false) }
    end

    # Minimizes the window and returns +nil+. Runs as #center does.
    #
    # Mirrors Tauri's Window::minimize (window/mod.rs:1760; lib.rs:3355).
    #
    # === Example
    #
    #   window.minimize
    def minimize
      native = @native
      dispatch { native.set_minimized(true) }
    end

    # Brings a minimized window back and returns +nil+. Runs as #center
    # does.
    #
    # Mirrors Tauri's Window::unminimize (window/mod.rs:1765;
    # lib.rs:3356).
    #
    # === Example
    #
    #   window.unminimize
    def unminimize
      native = @native
      dispatch { native.set_minimized(false) }
    end

    # Shows the window and returns +nil+. Runs as #center does.
    #
    # Mirrors Tauri's Window::show (window/mod.rs:1770; lib.rs:3358).
    #
    # === Example
    #
    #   window.show
    def show
      native = @native
      dispatch { native.set_visible(true) }
    end

    # Hides the window and returns +nil+. Runs as #center does.
    #
    # Mirrors Tauri's Window::hide (window/mod.rs:1775; lib.rs:3359).
    #
    # === Example
    #
    #   window.hide
    def hide
      native = @native
      dispatch { native.set_visible(false) }
    end

    # Gives the window its frame and title bar, or takes them away, and
    # returns +nil+. Runs as #center does.
    #
    # On Windows a resizable window without decorations can still be
    # resized by its edges, as #set_resizable describes; this attaches or
    # removes the cover that makes it so (plan 041, decision 5).
    #
    # Mirrors Tauri's Window::set_decorations (window/mod.rs:1792;
    # lib.rs:3366-3377; undecorated_resizing.rs:117-196, 403-411).
    #
    # === Example
    #
    #   window.set_decorations(false)
    def set_decorations(decorations)
      native = @native
      dispatch { native.set_decorations(decorations) }
    end

    # Keeps the window below every other window, or lets it go back among
    # them, and returns +nil+. Runs as #center does.
    #
    # Mirrors Tauri's Window::set_always_on_bottom (window/mod.rs:1858;
    # lib.rs:3387-3389).
    #
    # === Example
    #
    #   window.set_always_on_bottom(true)
    def set_always_on_bottom(always_on_bottom)
      native = @native
      dispatch { native.set_always_on_bottom(always_on_bottom) }
    end

    # Shows the window on every workspace, or on its own, and returns
    # +nil+. Runs as #center does. Windows has no such setting, so there
    # it does nothing.
    #
    # Mirrors Tauri's Window::set_visible_on_all_workspaces
    # (window/mod.rs:1880; lib.rs:3391-3393).
    #
    # === Example
    #
    #   window.set_visible_on_all_workspaces(true)
    def set_visible_on_all_workspaces(visible_on_all_workspaces)
      native = @native
      dispatch { native.set_visible_on_all_workspaces(visible_on_all_workspaces) }
    end

    # Keeps other apps from capturing the window's contents, as a
    # screenshot or a screen share would, or lets them again, and returns
    # +nil+. Runs as #center does. Linux has no such setting, so there it
    # does nothing.
    #
    # Mirrors Tauri's Window::set_content_protected (window/mod.rs:1906;
    # lib.rs:3394).
    #
    # === Example
    #
    #   window.set_content_protected(true)
    def set_content_protected(protected)
      native = @native
      dispatch { native.set_content_protection(protected) }
    end

    # Resizes the window's client area to +size+, a LogicalSize or a
    # PhysicalSize, and returns +nil+. Runs as #center does; any other
    # argument raises TypeError on the calling thread.
    #
    # Mirrors Tauri's Window::set_size (window/mod.rs:1915; lib.rs:3395-3397).
    # Tauri takes anything that converts into its Size; Ruby has no such
    # conversion, so this takes either kind of size (plan 040, decision 2).
    #
    # === Example
    #
    #   window.set_size(Tokra::LogicalSize.new(width: 1024, height: 768))
    def set_size(size)
      native = @native
      dimensions = size_dimensions(size)
      dispatch { native.set_inner_size(dimensions) }
    end

    # Keeps the window's client area at least +size+, a LogicalSize or a
    # PhysicalSize, or with no minimum for +nil+, and returns +nil+. Runs
    # as #set_size does.
    #
    # Mirrors Tauri's Window::set_min_size (window/mod.rs:1924;
    # lib.rs:3398-3400).
    #
    # === Example
    #
    #   window.set_min_size(Tokra::LogicalSize.new(width: 400, height: 300))
    def set_min_size(size)
      native = @native
      dimensions = size && size_dimensions(size)
      dispatch { native.set_min_inner_size(dimensions) }
    end

    # Keeps the window's client area at most +size+, a LogicalSize or a
    # PhysicalSize, or with no maximum for +nil+, and returns +nil+. Runs
    # as #set_size does.
    #
    # Mirrors Tauri's Window::set_max_size (window/mod.rs:1933;
    # lib.rs:3401-3403).
    #
    # === Example
    #
    #   window.set_max_size(nil)
    def set_max_size(size)
      native = @native
      dimensions = size && size_dimensions(size)
      dispatch { native.set_max_inner_size(dimensions) }
    end

    # Moves the window's frame so its top-left corner is at +position+, a
    # LogicalPosition or a PhysicalPosition relative to the desktop, and
    # returns +nil+. Runs as #set_size does.
    #
    # Mirrors Tauri's Window::set_position (window/mod.rs:1954;
    # lib.rs:3412-3414).
    #
    # === Example
    #
    #   window.set_position(Tokra::LogicalPosition.new(x: 100, y: 100))
    def set_position(position)
      native = @native
      dimensions = position_dimensions(position)
      dispatch { native.set_outer_position(dimensions) }
    end

    # Makes the window fill its monitor, without a frame, or puts it back,
    # and returns +nil+. Runs as #center does. On macOS the window moves to
    # a Space of its own; #set_simple_fullscreen does not.
    #
    # Mirrors Tauri's Window::set_fullscreen (window/mod.rs:1963;
    # lib.rs:3415-3421).
    #
    # === Example
    #
    #   window.set_fullscreen(true)
    def set_fullscreen(fullscreen)
      native = @native
      dispatch { native.set_fullscreen(fullscreen) }
    end

    # Makes the window fill its monitor in the Space it is in, the way
    # macOS apps did before fullscreen Spaces, or puts it back, and returns
    # +nil+. Elsewhere it is #set_fullscreen. Runs as #center does.
    #
    # Mirrors Tauri's Window::set_simple_fullscreen (window/mod.rs:1981;
    # lib.rs:3424-3427).
    #
    # === Example
    #
    #   window.set_simple_fullscreen(true)
    def set_simple_fullscreen(enable)
      native = @native
      dispatch { native.set_simple_fullscreen(enable) }
    end

    # Brings the window to the front and gives it the keyboard, and
    # returns +nil+. Runs as #center does. On macOS an app whose
    # activation policy is ActivationPolicy::Prohibited never comes to the
    # front.
    #
    # Mirrors Tauri's Window::set_focus (window/mod.rs:1995;
    # lib.rs:3428-3430).
    #
    # === Example
    #
    #   window.set_focus
    def set_focus
      native = @native
      dispatch { native.set_focus }
    end

    # Lets the window take the keyboard, or keeps it from doing so, and
    # returns +nil+. Runs as #center does. On macOS a window that already
    # has the keyboard keeps it.
    #
    # Mirrors Tauri's Window::set_focusable (window/mod.rs:2005;
    # lib.rs:3431-3433).
    #
    # === Example
    #
    #   window.set_focusable(false)
    def set_focusable(focusable)
      native = @native
      dispatch { native.set_focusable(focusable) }
    end

    # Hides the window's taskbar button, or shows it again, and returns
    # +nil+. Runs as #center does. macOS has no taskbar, so there it does
    # nothing.
    #
    # Mirrors Tauri's Window::set_skip_taskbar (window/mod.rs:2027;
    # lib.rs:3438-3448).
    #
    # === Example
    #
    #   window.set_skip_taskbar(true)
    def set_skip_taskbar(skip)
      native = @native
      dispatch { native.set_skip_taskbar(skip) }
    end

    # Keeps the cursor inside the window, or lets it leave, and returns
    # +nil+. Runs as #center does. A platform that refuses says nothing,
    # as in Tauri.
    #
    # Mirrors Tauri's Window::set_cursor_grab (window/mod.rs:2044;
    # lib.rs:3449-3451).
    #
    # === Example
    #
    #   window.set_cursor_grab(true)
    def set_cursor_grab(grab)
      native = @native
      dispatch { native.set_cursor_grab(grab) }
    end

    # Shows the cursor over the window, or hides it, and returns +nil+.
    # Runs as #center does.
    #
    # Mirrors Tauri's Window::set_cursor_visible (window/mod.rs:2061;
    # lib.rs:3452-3454).
    #
    # === Example
    #
    #   window.set_cursor_visible(false)
    def set_cursor_visible(visible)
      native = @native
      dispatch { native.set_cursor_visible(visible) }
    end

    # Shows +icon+, a CursorIcon, as the cursor over the window and
    # returns +nil+. Runs as #center does; any other argument raises
    # TypeError on the calling thread.
    #
    # Mirrors Tauri's Window::set_cursor_icon (window/mod.rs:2070;
    # lib.rs:3455-3457, 708-753).
    #
    # === Example
    #
    #   window.set_cursor_icon(Tokra::CursorIcon::Wait)
    def set_cursor_icon(icon)
      native = @native
      expect(icon, CursorIcon)
      name = icon.name
      dispatch { native.set_cursor_icon(name) }
    end

    # Moves the cursor to +position+, a LogicalPosition or a
    # PhysicalPosition relative to the window's client area, and returns
    # +nil+. Runs as #set_size does. A platform that refuses says nothing,
    # as in Tauri.
    #
    # Mirrors Tauri's Window::set_cursor_position (window/mod.rs:2079;
    # lib.rs:3458-3460).
    #
    # === Example
    #
    #   window.set_cursor_position(Tokra::LogicalPosition.new(x: 10, y: 10))
    def set_cursor_position(position)
      native = @native
      dimensions = position_dimensions(position)
      dispatch { native.set_cursor_position(dimensions) }
    end

    # Starts moving the window with the mouse, as a drag on its title bar
    # would, and returns +nil+. Call it while the left mouse button is
    # down, as from a mousedown handler; otherwise nothing happens. Runs as
    # #center does.
    #
    # Mirrors Tauri's Window::start_dragging (window/mod.rs:2097;
    # lib.rs:3464-3466).
    #
    # === Example
    #
    #   window.start_dragging
    def start_dragging
      native = @native
      dispatch { native.drag_window }
    end

    # Starts resizing the window with the mouse from +direction+, a
    # ResizeDirection, and returns +nil+. Call it while the left mouse
    # button is down, as #start_dragging asks. Runs as #center does; any
    # other argument raises TypeError on the calling thread.
    #
    # Mirrors Tauri's Window::start_resize_dragging (window/mod.rs:2102;
    # lib.rs:3467-3478).
    #
    # === Example
    #
    #   window.start_resize_dragging(Tokra::ResizeDirection::SouthEast)
    def start_resize_dragging(direction)
      native = @native
      expect(direction, ResizeDirection)
      name = direction.name
      dispatch { native.drag_resize_window(name) }
    end

    # Shows the window in +theme+, a Theme, or in the system's theme for
    # +nil+, and returns +nil+. Runs as #center does; any other argument
    # raises TypeError on the calling thread.
    #
    # On Windows the window's menu bar, if it has one, follows: Light or
    # Dark, and for +nil+ the system's.
    #
    # Mirrors Tauri's Window::set_theme (window/mod.rs:2185-2206;
    # lib.rs:3539-3541, 5224-5230), which then themes the window's menu
    # on Windows through muda's set_theme_for_hwnd.
    #
    # === Example
    #
    #   window.set_theme(Tokra::Theme::Dark)
    def set_theme(theme)
      native = @native
      expect(theme, Theme) if theme
      name = theme&.name
      dispatch { native.set_theme(name) }
      current = menu
      if current && native.respond_to?(:set_menu_theme)
        native_menu = current.native #: Native::Menu
        dispatch { native.set_menu_theme(native_menu, name) }
      end
      nil
    end

    # Whether the window takes input. Answers as #scale_factor does.
    #
    # On macOS a disabled window has a sheet attached, as #set_enabled
    # leaves it; on Linux it is GTK's sensitivity, and on Windows Win32's
    # enabled state.
    #
    # Mirrors Tauri's Window::is_enabled (window/mod.rs:1443; lib.rs:3330),
    # which tauri-runtime-wry's WindowExt implements for each platform
    # (window/macos.rs:35-38, linux.rs:20-22, windows.rs:18-20).
    #
    # === Example
    #
    #   window.is_enabled  #=> true
    def is_enabled
      native = @native
      getter { native.is_enabled }
    end

    # Lets the window take input, or stops it, and returns +nil+. Runs as
    # #center does.
    #
    # On macOS disabling attaches a half-transparent sheet the size of the
    # window, as Electron does, and enabling ends it; on Linux it changes
    # GTK's sensitivity, and on Windows it calls EnableWindow.
    #
    # Mirrors Tauri's Window::set_enabled (window/mod.rs:1741; lib.rs:3357),
    # with WindowExt's code for each platform (window/macos.rs:12-33,
    # linux.rs:16-18, windows.rs:14-16).
    #
    # === Example
    #
    #   window.set_enabled(false)
    def set_enabled(enabled)
      native = @native
      dispatch { native.set_enabled(enabled) }
    end

    # The mouse cursor's position on the desktop, a PhysicalPosition, as
    # AppHandle#cursor_position answers it.
    #
    # Mirrors Tauri's Window::cursor_position (window/mod.rs:1643-1645),
    # which asks its app handle.
    #
    # === Example
    #
    #   window.cursor_position  #=> #<data Tokra::PhysicalPosition x=812.0, y=455.5>
    def cursor_position
      @app_handle.cursor_position
    end

    # Limits the window's client area one side at a time, as +constraints+,
    # a WindowSizeConstraints, says, and returns +nil+. Runs as #set_size
    # does; any other argument raises TypeError on the calling thread.
    #
    # Mirrors Tauri's Window::set_size_constraints (window/mod.rs:1942;
    # lib.rs:3404-3411), which hands tao the same four limits.
    #
    # === Example
    #
    #   window.set_size_constraints(Tokra::WindowSizeConstraints.new(min_width: Tokra::LogicalUnit.new(400)))
    def set_size_constraints(constraints)
      native = @native
      expect(constraints, WindowSizeConstraints)
      limits = [constraints.min_width, constraints.min_height, constraints.max_width, constraints.max_height]
        .map { |limit| limit && unit_dimension(limit) }
      dispatch { native.set_inner_size_constraints(limits) }
    end

    # Sets the window's icon to +image+, a Tokra::Image, and returns +nil+.
    # Runs as #center does. macOS has no window icons, so there it does
    # nothing.
    #
    # The image becomes an icon on the calling thread, as in Tauri, so an
    # image whose pixels do not fill its width and height raises
    # Error::Runtime "invalid icon: ..." here, with tao's reason, and
    # nothing is sent. On Linux tao checks nothing and GTK would end the
    # process instead; Tokra checks there as tao does elsewhere (plan 041,
    # decision 4). Anything but an Image raises TypeError.
    #
    # Mirrors Tauri's Window::set_icon (window/mod.rs:2014), which converts
    # the image into tao's icon before sending it (image/mod.rs:130-138;
    # tauri-runtime-wry lib.rs:490-499, 2278-2286, 3434-3436).
    #
    # === Example
    #
    #   window.set_icon(Tokra::Image.from_path("icons/32x32.png"))
    def set_icon(image)
      native = @native
      expect(image, Image)
      icon = begin
        Native::Icon.from_rgba(image.rgba, image.width, image.height)
      rescue RuntimeError => e
        raise Error::Runtime, "invalid icon: #{e.message}"
      end
      dispatch { native.set_window_icon(icon) }
    end

    # Colors the window behind its content with +color+, a Tokra::Color,
    # or the platform's default for +nil+, and returns +nil+. Runs as
    # #center does. On Windows the alpha is ignored.
    #
    # The webview fills the window and paints its own background, so this
    # shows only where the webview does not; Webview#set_background_color
    # colors the webview. Tauri's WebviewWindow sets both, and Tokra has no
    # WebviewWindow, so call both for that (plan 041, decision 2).
    #
    # Mirrors Tauri's Window::set_background_color (window/mod.rs:1897;
    # lib.rs:3542-3544).
    #
    # === Example
    #
    #   window.set_background_color(Tokra::Color.from_str("#1e1e1e"))
    def set_background_color(color)
      native = @native
      expect(color, Color) if color
      rgba = color && [color.red, color.green, color.blue, color.alpha] #: Native::Window::rgba?
      dispatch { native.set_background_color(rgba) }
    end

    # Gives the window a shadow, or takes it away, and returns +nil+. Runs
    # as #center does.
    #
    # On macOS it is AppKit's window shadow. On Windows it matters only for
    # an undecorated window: +true+ draws a thin border and, on Windows 11,
    # rounded corners, and the edges a person drags to resize it follow.
    # Linux has no such setting, so there it does nothing.
    #
    # Mirrors Tauri's Window::set_shadow (window/mod.rs:1809;
    # lib.rs:3378-3385), with Tauri's undecorated resizing on Windows
    # (undecorated_resizing.rs:443-475).
    #
    # === Example
    #
    #   window.set_shadow(false)
    def set_shadow(enable)
      native = @native
      dispatch { native.set_shadow(enable) }
    end

    # Asks to close this window and returns +nil+.
    #
    # Closing works like a click on the close button: your
    # Builder#on_window_event listeners, plugins, and the App#run callback
    # hear WindowEvent::CloseRequested on a later turn of the event loop,
    # and the window closes unless one of them calls
    # <tt>api.prevent_close</tt>. When the last window closes, the app asks
    # to exit (RunEvent::ExitRequested). Use #destroy to close without
    # asking. Raises Error::Runtime when the event loop has ended.
    #
    # Mirrors Tauri's Window::close (window/mod.rs:1779-1782), which sends
    # WindowMessage::Close through the loop (tauri-runtime-wry
    # lib.rs:2142-2149, 4229-4231).
    #
    # === Example
    #
    #   window.close
    def close
      @app_handle.runtime_context.request_close
    end

    # Closes this window without asking and returns +nil+.
    #
    # Similar to #close, but no WindowEvent::CloseRequested is emitted and
    # nothing can keep the window open. Handlers still hear
    # WindowEvent::Destroyed, and when the last window goes the app still
    # asks to exit. On the main thread the window closes at once, where
    # Tauri queues the close through the event loop; Destroyed comes later
    # from the platform either way. From another thread the close travels
    # to the main thread. Raises Error::Runtime when the event loop has
    # ended.
    #
    # Mirrors Tauri's Window::destroy (window/mod.rs:1784-1787), which
    # drops the native window (tauri-runtime-wry lib.rs:2151-2160,
    # 4232-4234, 4293-4298).
    #
    # === Example
    #
    #   window.destroy
    def destroy
      native = @native
      dispatch { native.close }
    end

    # The native name of this window: a RawWindowHandle value.
    #
    # A library that opens a dialog in front of your window, or draws into
    # it, asks for the window's handle. On Windows the answer is a
    # RawWindowHandle::Win32WindowHandle, on macOS a
    # RawWindowHandle::AppKitWindowHandle, and on Linux a
    # RawWindowHandle::XlibWindowHandle under X11 or a
    # RawWindowHandle::WaylandWindowHandle under Wayland.
    #
    # From another thread this asks the main thread and waits for its
    # answer, as Tauri's does. Called from another thread once the event
    # loop has ended, it raises RawWindowHandle::HandleError::Unavailable,
    # where Tauri raises it for a closed window: a Tokra window closes only
    # when its loop ends. On the main thread, in a RunEvent::Exit handler
    # or an +at_exit+ hook, it still answers, since the window still
    # exists.
    #
    # The handle names the window only while it is open. RawWindowHandle
    # says how to use one safely.
    #
    # Mirrors Tauri's <tt>HasWindowHandle</tt> for Window
    # (window/mod.rs:943-949), which asks the runtime's dispatcher, a
    # getter answered on the main thread, and turns a failed getter into
    # <tt>HandleError::Unavailable</tt> (tauri-runtime-wry
    # lib.rs:1852-1856, 2012-2018, 3320-3326).
    #
    # === Example
    #
    #   window.window_handle  #=> #<data Tokra::RawWindowHandle::AppKitWindowHandle ns_view=105553116266496>
    def window_handle
      native = @native
      RawWindowHandle.window_handle(@app_handle.runtime_context.getter { native.raw_window_handle })
    rescue Error::Runtime
      raise RawWindowHandle::HandleError::Unavailable
    end

    # The native name of the display this window is on: a RawWindowHandle
    # value, as AppHandle#display_handle answers.
    #
    # Pair it with #window_handle when a library asks for both, as a
    # dialog that names its parent window does.
    #
    # Mirrors Tauri's <tt>HasDisplayHandle</tt> for Window
    # (window/mod.rs:951-957), which asks the app handle.
    #
    # === Example
    #
    #   window.display_handle  #=> #<data Tokra::RawWindowHandle::AppKitDisplayHandle>
    def display_handle
      @app_handle.display_handle
    end

    # Runs the block on the main thread and returns +nil+, as
    # AppHandle#run_on_main_thread does.
    #
    # Mirrors Tauri's Window::run_on_main_thread (window/mod.rs:1087-1094).
    #
    # === Example
    #
    #   Thread.new { window.run_on_main_thread { window.native.set_title("Ready") } }
    def run_on_main_thread(&)
      @app_handle.runtime_context.run_on_main_thread(&)
    end

    # Sends a native call to the main thread without waiting for it.
    private def dispatch(&call)
      @app_handle.runtime_context.run_on_main_thread(&call)
    end

    # Runs a native query on the main thread and answers it. A closed
    # window answers +nil+, and Tauri's runtime leaves a closed window's
    # getter unanswered (lib.rs:3244-3250), so +nil+ raises.
    private def getter(&query)
      value = @app_handle.runtime_context.getter(&query)
      raise Error::Runtime, Error::Runtime::FAILED_TO_RECEIVE_MESSAGE if value.nil?

      value
    end

    # The PhysicalPosition in a native <tt>[[x, y]]</tt> answer. tao's
    # NotSupportedError, <tt>[nil]</tt>, is the failure Tauri's handler
    # sends back as FailedToSendMessage (lib.rs:3261-3276).
    private def physical_position(answer)
      position = answer.first
      raise Error::Runtime, Error::Runtime::FAILED_TO_SEND_MESSAGE unless position

      x, y = position
      PhysicalPosition.new(x:, y:)
    end

    # The Monitor in a native <tt>[monitor]</tt> answer, or +nil+ for
    # <tt>[nil]</tt>.
    private def maybe_monitor(answer)
      entry = answer.first
      entry && Monitor.from_native(entry)
    end

    # The native <tt>[physical, width, height]</tt> for a LogicalSize or a
    # PhysicalSize.
    private def size_dimensions(size)
      case size
      when LogicalSize then [false, Float(size.width), Float(size.height)]
      when PhysicalSize then [true, Float(size.width), Float(size.height)]
      else raise TypeError, "wrong argument type #{size.class} (expected Tokra::LogicalSize or Tokra::PhysicalSize)"
      end
    end

    # The native <tt>[physical, x, y]</tt> for a LogicalPosition or a
    # PhysicalPosition.
    private def position_dimensions(position)
      Dpi.position_dimensions(position)
    end

    # The native <tt>[physical, value]</tt> for a LogicalUnit or a
    # PhysicalUnit.
    private def unit_dimension(unit)
      [unit.is_a?(PhysicalUnit), Float(unit.value)]
    end

    # Raises TypeError, in Ruby's words, unless +value+ is a +type+.
    private def expect(value, type)
      raise TypeError, "wrong argument type #{value.class} (expected #{type})" unless value.is_a?(type)

      nil
    end
  end
end

# SPDX-SnippetEnd
