# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Window events as tauri:// events adapted from
#                      tauri/crates/tauri/src/manager/window.rs

module Tokra
  # What the app's manager does with a window's events: it tells the
  # page and Ruby listeners as <tt>tauri://</tt> events, and lets a page
  # that listens for <tt>tauri://close-requested</tt> decide the close.
  #
  # Mirrors the free function on_window_event and the Window helpers in
  # Tauri's manager/window.rs.
  module WindowManager # :nodoc:
    WINDOW_RESIZED_EVENT = "tauri://resize"
    WINDOW_MOVED_EVENT = "tauri://move"
    WINDOW_CLOSE_REQUESTED_EVENT = "tauri://close-requested"
    WINDOW_DESTROYED_EVENT = "tauri://destroyed"
    WINDOW_FOCUS_EVENT = "tauri://focus"
    WINDOW_BLUR_EVENT = "tauri://blur"
    WINDOW_SCALE_FACTOR_CHANGED_EVENT = "tauri://scale-change"
    WINDOW_THEME_CHANGED = "tauri://theme-changed"
    DRAG_ENTER_EVENT = "tauri://drag-enter"
    DRAG_OVER_EVENT = "tauri://drag-over"
    DRAG_DROP_EVENT = "tauri://drag-drop"
    DRAG_LEAVE_EVENT = "tauri://drag-leave"

    WINDOW_CREATED_EVENT = "tauri://window-created"

    # Joins +window+ to the app, as attach_window does
    # (manager/window.rs:79-124): its first listener tells the page and
    # Ruby listeners of each event, then calls each Builder#on_window_event
    # block; the manager holds it; and every plugin hears window_created
    # on the main thread. Answers +window+.
    def self.attach_window(window)
      handle = window.app_handle
      listeners = handle.window_event_listeners
      window.on_window_event do |event|
        on_window_event(window, event)
        listeners.each { |listener| listener.call(window, event) }
      end
      handle.windows[window.label] = window
      plugins = handle.manager.plugins
      handle.run_on_main_thread { plugins.window_created(window) }
      window
    end

    # Emits +event+ as its <tt>tauri://</tt> event (manager/window.rs:162-270).
    # Tokra's windows are webview windows, so drag and drop go to every
    # target with the window's label.
    def self.on_window_event(window, event)
      case event
      when WindowEvent::Resized
        emit_to_window(window, WINDOW_RESIZED_EVENT, size_json(event.size))
      when WindowEvent::Moved
        emit_to_window(window, WINDOW_MOVED_EVENT, { "x" => event.position.x, "y" => event.position.y })
      when WindowEvent::CloseRequested
        event.api.prevent_close if has_js_listener?(window, WINDOW_CLOSE_REQUESTED_EVENT)
        emit_to_window(window, WINDOW_CLOSE_REQUESTED_EVENT, nil)
      when WindowEvent::Destroyed
        emit_to_window(window, WINDOW_DESTROYED_EVENT, nil)
      when WindowEvent::Focused
        emit_to_window(window, event.focused ? WINDOW_FOCUS_EVENT : WINDOW_BLUR_EVENT, nil)
      when WindowEvent::ScaleFactorChanged
        emit_to_window(window, WINDOW_SCALE_FACTOR_CHANGED_EVENT,
          { "scaleFactor" => event.scale_factor, "size" => size_json(event.new_inner_size) })
      when WindowEvent::DragDrop
        drag_drop(window, event.event)
      when WindowEvent::ThemeChanged
        emit_to_window(window, WINDOW_THEME_CHANGED, event.theme.name.downcase)
      end
      nil
    end

    # Emits to the Window and WebviewWindow targets with the window's
    # label (manager/window.rs:125-138).
    def self.emit_to_window(window, event, payload)
      label = window.label
      window.app_handle.manager.emit_filter(Event::EmitArgs.serialize(event, payload), lambda { |target|
        (target.is_a?(EventTarget::Window) || target.is_a?(EventTarget::WebviewWindow)) && target.label == label
      })
    end

    # Whether a page listens for +event+ on the window's Window or
    # WebviewWindow target (manager/window.rs:140-148).
    def self.has_js_listener?(window, event)
      label = window.label
      window.app_handle.manager.listeners.has_js_listener?(event) do |target|
        (target.is_a?(EventTarget::Window) || target.is_a?(EventTarget::WebviewWindow)) && target.label == label
      end
    end

    # A webview window's drops go to its label (manager/window.rs:194-266).
    # Tauri also widens its fs scope to a dropped path; Tokra has none.
    def self.drag_drop(window, event)
      name, payload = case event
      when DragDropEvent::Enter then [DRAG_ENTER_EVENT, drag_drop_payload(event.paths, event.position)]
      when DragDropEvent::Over then [DRAG_OVER_EVENT, drag_drop_payload(nil, event.position)]
      when DragDropEvent::Drop then [DRAG_DROP_EVENT, drag_drop_payload(event.paths, event.position)]
      else [DRAG_LEAVE_EVENT, nil]
      end
      window.app_handle.manager.emit_to(EventTarget.labeled(window.label), Event::EmitArgs.serialize(name, payload))
    end

    # Tauri's DragDropPayload, whose +paths+ serde skips when absent
    # (manager/window.rs:150-156).
    def self.drag_drop_payload(paths, position)
      payload = {} #: Hash[String, json_value]
      payload["paths"] = paths.map(&:to_s) if paths
      payload["position"] = { "x" => position.x, "y" => position.y }
      payload
    end

    def self.size_json(size)
      { "width" => size.width, "height" => size.height }
    end
  end
end

# SPDX-SnippetEnd
