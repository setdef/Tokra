# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "forwardable"

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: WebviewWindow adapted from tauri/crates/tauri/src/webview/webview_window.rs

module Tokra
  # A window and the one webview that fills it, as one object.
  #
  # Most windows an app opens hold a single page. Such a window is two
  # things underneath, a Window and a Webview, which share a label: the
  # window has the title, the size, and the menu; the webview has the page.
  # Reaching for the right one for each call gets tedious.
  #
  # A WebviewWindow answers both. WebviewWindowBuilder#build makes one,
  # and Manager#get_webview_window finds one by label. Each call goes to
  # the half Tauri sends it to:
  #
  # [The window] the menu methods (#on_menu_event, #menu, #set_menu,
  #              #remove_menu, #hide_menu, #show_menu, #is_menu_visible,
  #              #popup_menu, #popup_menu_at); the getters (#scale_factor,
  #              #inner_position, #outer_position, #inner_size,
  #              #outer_size, #is_fullscreen, #is_minimized,
  #              #is_maximized, #is_focused, #is_decorated, #is_resizable,
  #              #is_enabled, #is_always_on_top, #is_maximizable,
  #              #is_minimizable, #is_closable, #is_visible, #title,
  #              #current_monitor, #primary_monitor, #monitor_from_point,
  #              #available_monitors, #theme); the setters (#center,
  #              #request_user_attention, #set_resizable, #set_enabled,
  #              #set_maximizable, #set_minimizable, #set_closable,
  #              #set_title, #maximize, #unmaximize, #minimize,
  #              #unminimize, #show, #hide, #close, #destroy,
  #              #set_decorations, #set_shadow, #set_effects,
  #              #set_always_on_bottom, #set_always_on_top,
  #              #set_visible_on_all_workspaces, #set_content_protected,
  #              #set_size, #set_min_size, #set_max_size,
  #              #set_size_constraints, #set_position, #set_fullscreen,
  #              #set_simple_fullscreen, #set_focus, #set_focusable,
  #              #set_icon, #set_skip_taskbar, #set_cursor_grab,
  #              #set_cursor_visible, #set_cursor_icon,
  #              #set_cursor_position, #set_ignore_cursor_events,
  #              #start_dragging, #set_badge_count, #set_progress_bar,
  #              #set_title_bar_style, #set_theme, and on macOS
  #              #set_badge_label, on Windows #set_overlay_icon);
  #              #on_window_event; and #window_handle.
  # [The webview] #label, #run_on_main_thread, #eval, #cursor_position,
  #               and #resources_table.
  # [Both] #set_background_color colors the window, then the webview.
  #
  # Each behaves as its Window or Webview method does; see there. Listener
  # methods hear events sent to the WebviewWindow target with its label,
  # and the Emitter and Manager methods reach the app as any handle does.
  #
  # Mirrors Tauri's WebviewWindow (webview_window.rs:1382-2599). The
  # methods Tokra's Window and Webview lack (url, navigate, reload,
  # print, zoom, cookies, devtools, on_webview_event) arrive with them
  # (plan 052, phases 4 and 5).
  #
  # === Example
  #
  #   settings = app.get_webview_window("settings")
  #   settings.set_title("Settings (2)")
  #   settings.eval("location.reload()")
  class WebviewWindow
    extend Forwardable
    include Manager
    include Listener
    include Emitter

    # The window half.
    attr_reader :window

    # The webview half.
    attr_reader :webview

    # Pairs +window+ with +webview+, which share a label. The app makes
    # these; WebviewWindowBuilder#build and Manager#get_webview_window
    # answer them.
    def initialize(window:, webview:) # :nodoc:
      @window = window
      @webview = webview
    end

    # Menu APIs (webview_window.rs:1521-1625).
    def_delegators :@window, :on_menu_event, :menu, :set_menu, :remove_menu, :hide_menu, :show_menu,
      :is_menu_visible, :popup_menu, :popup_menu_at

    # Window getters (webview_window.rs:1626-1818).
    def_delegators :@window, :scale_factor, :inner_position, :outer_position, :inner_size, :outer_size,
      :is_fullscreen, :is_minimized, :is_maximized, :is_focused, :is_decorated, :is_resizable, :is_enabled,
      :is_always_on_top, :is_maximizable, :is_minimizable, :is_closable, :is_visible, :title,
      :current_monitor, :primary_monitor, :monitor_from_point, :available_monitors, :theme

    # Window setters (webview_window.rs:1835-2218).
    def_delegators :@window, :center, :request_user_attention, :set_resizable, :set_enabled, :set_maximizable,
      :set_minimizable, :set_closable, :set_title, :maximize, :unmaximize, :minimize, :unminimize, :show, :hide,
      :close, :destroy, :set_decorations, :set_shadow, :set_effects, :set_always_on_bottom, :set_always_on_top,
      :set_visible_on_all_workspaces, :set_content_protected, :set_size, :set_min_size, :set_max_size,
      :set_size_constraints, :set_position, :set_fullscreen, :set_simple_fullscreen, :set_focus, :set_focusable,
      :set_icon, :set_skip_taskbar, :set_cursor_grab, :set_cursor_visible, :set_cursor_icon, :set_cursor_position,
      :set_ignore_cursor_events, :start_dragging, :set_badge_count, :set_progress_bar, :set_title_bar_style,
      :set_theme

    # The window's events and its raw handle (webview_window.rs:1464-1467,
    # 1409-1417).
    def_delegators :@window, :on_window_event, :window_handle

    # The webview's (webview_window.rs:1454-1462, 1820-1831, 2322-2325,
    # 2573-2581).
    def_delegators :@webview, :label, :run_on_main_thread, :eval, :cursor_position, :resources_table

    # The app handle, as the webview reaches it.
    def app_handle
      @webview.app_handle
    end

    # Paints the window's background, then the webview's, with +color+,
    # a Tokra::Color, or the default for +nil+, and returns +nil+, as
    # Window#set_background_color and then Webview#set_background_color
    # do.
    #
    # Mirrors Tauri's WebviewWindow::set_background_color
    # (webview_window.rs:2104-2107).
    #
    # === Example
    #
    #   settings.set_background_color(Tokra::Color.new(30, 30, 30, 255))
    def set_background_color(color)
      @window.set_background_color(color)
      @webview.set_background_color(color)
    end

    # The native name of the display this window is on, as
    # AppHandle#display_handle answers (webview_window.rs:1419-1426).
    def display_handle
      @webview.app_handle.display_handle
    end

    # Calls the block with each +event+ sent to this webview window, by
    # Emitter#emit, or to its label as a WebviewWindow or an AnyLabel, and
    # returns the handler's id. Raises Error::IllegalEventName for a bad
    # name.
    #
    # Mirrors Tauri's Listener for WebviewWindow (webview_window.rs:2493-2505).
    #
    # === Example
    #
    #   settings.listen("saved") { |event| puts event.payload }
    def listen(event, &handler)
      app_handle.manager.listen(Event::Name.check(event), EventTarget.webview_window(label), &handler)
    end

    # Calls the block with the next +event+ sent to this webview window,
    # as #listen does, and returns the handler's id
    # (webview_window.rs:2507-2519).
    def once(event, &handler)
      app_handle.manager.once(Event::Name.check(event), EventTarget.webview_window(label), &handler)
    end

    # Removes the handler with +id+, whichever target it listens for
    # (webview_window.rs:2521-2523).
    def unlisten(id)
      app_handle.manager.unlisten(id)
    end

    # Whether +other+ is a WebviewWindow with the same webview, as Tauri
    # compares only the webviews (webview_window.rs:1401-1406).
    def ==(other)
      other.is_a?(WebviewWindow) && other.webview == @webview
    end
    alias eql? ==

    # A hash that agrees with #==.
    def hash
      [WebviewWindow, @webview].hash
    end
  end
end

# SPDX-SnippetEnd
