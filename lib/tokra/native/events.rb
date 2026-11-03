# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Tokra
  module Native
    # IPC message received from WebView JavaScript.
    #
    # Created when JavaScript calls +window.ipc.postMessage()+. +label+ is
    # the label of the webview that posted it, which its handler captured
    # (tauri-runtime-wry lib.rs:5169-5192); +message+ is the posted string;
    # +url+ is the URL of the frame that posted it, which wry reports as the
    # request URI and Tauri treats as the invoke origin (ipc/protocol.rs
    # handle_ipc_message).
    #
    #   case event
    #   when Tokra::Native::IpcEvent
    #     puts "#{event.label} sent #{event.message} from #{event.url}"
    #   end
    IpcEvent = Data.define(:label, :message, :url)

    # Wake-up signal from a Ractor via Proxy.
    #
    # Created when a worker Ractor calls +proxy.wake_up(payload)+.
    #
    #   case event
    #   when Tokra::Native::WakeUpEvent
    #     result = JSON.parse(event.payload)
    #     # Handle worker result...
    #   end
    WakeUpEvent = Data.define(:payload)

    # Window close requested, for the window labeled +label+.
    #
    # Created when the user clicks the window close button, or when
    # Proxy#request_close asks for the same. The loop keeps running: the
    # App asks its handlers and closes the native window unless one
    # prevents it (tauri-runtime-wry lib.rs:4262-4290).
    #
    #   case event
    #   when Tokra::Native::WindowCloseEvent
    #     windows[event.label].close unless keep_open?
    #   end
    WindowCloseEvent = Data.define(:label)

    # The native window labeled +label+ is gone.
    #
    # Created from tao's <tt>WindowEvent::Destroyed</tt>, which follows
    # Window#close. The callback's answer matters for this event: +true+
    # ends the loop with status 0, as the last window's exit request does
    # in Tauri's runtime (tauri-runtime-wry lib.rs:4171-4185); any other
    # answer keeps it running.
    #
    #   case event
    #   when Tokra::Native::WindowDestroyedEvent
    #     windows.delete(event.label)
    #     windows.empty?
    #   end
    WindowDestroyedEvent = Data.define(:label)

    # SPDX-SnippetBegin
    # SPDX-License-Identifier: Apache-2.0 OR MIT
    # SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    # SPDX-SnippetComment: Window events adapted from tauri-runtime-wry/src/lib.rs (WindowEventWrapper)

    # The window's inner area changed size: tao's
    # <tt>WindowEvent::Resized</tt>. It carries no size, since Tauri's
    # runtime asks the window for its inner size instead of trusting
    # tao's, which wry's NSView makes unreliable on macOS
    # (tauri-runtime-wry lib.rs:557-575).
    #
    # Its +label+, as each window event's below, is the label of the
    # window tao reported it for, as Tauri's runtime names a window
    # event's window (tauri-runtime-wry lib.rs:4126-4150). The loop drops
    # an event for a window Native::Window.new did not build.
    WindowResizedEvent = Data.define(:label)

    # The window moved to (+x+, +y+), physical pixels: tao's
    # <tt>WindowEvent::Moved</tt>.
    WindowMovedEvent = Data.define(:label, :x, :y)

    # The window gained focus, +focused+ +true+, or lost it: tao's
    # <tt>WindowEvent::Focused</tt>, off Windows only. On Windows the
    # webview's focus stands in for its window's (WebviewFocusedEvent), as
    # Tauri's runtime takes it (tauri-runtime-wry lib.rs:521-549).
    WindowFocusedEvent = Data.define(:label, :focused)

    # The webview labeled +label+ gained focus, +focused+ +true+, or lost
    # it: WebView2's GotFocus and LostFocus, on Windows only. The App tells
    # the webview's window, as Tauri's runtime sends them as the window's
    # SynthesizedWindowEvent::Focused (tauri-runtime-wry lib.rs:4097-4122,
    # 5070-5128). Its +label+ is a webview's, where WindowFocusedEvent's is
    # a window's.
    WebviewFocusedEvent = Data.define(:label, :focused)

    # The window's scale factor changed to +scale_factor+, and its inner
    # area to +width+ by +height+ physical pixels: tao's
    # <tt>WindowEvent::ScaleFactorChanged</tt>.
    WindowScaleFactorChangedEvent = Data.define(:label, :scale_factor, :width, :height)

    # The system's theme changed: tao's <tt>WindowEvent::ThemeChanged</tt>,
    # +theme+ <tt>"light"</tt>, <tt>"dark"</tt>, or another name tao may
    # add.
    WindowThemeChangedEvent = Data.define(:label, :theme)

    # SPDX-SnippetEnd

    # Code asked the app to exit with +code+.
    #
    # Created for each Proxy#request_exit, Tauri's
    # <tt>Message::RequestExit</tt>. The callback's answer matters for this
    # event: +true+ ends the loop with +code+; any other answer keeps it
    # running (tauri-runtime-wry lib.rs:4215-4227).
    #
    #   case event
    #   when Tokra::Native::ExitRequestedEvent
    #     !keep_running?
    #   end
    ExitRequestedEvent = Data.define(:code)

    # HTTP request from WebView via the <tt>tokra://</tt> custom protocol.
    #
    # Contains all request data including a +request_id+ for correlating
    # the async response via +proxy.respond()+. +label+ is the label of the
    # webview that made the request, the id wry hands the protocol handler
    # (Tauri's protocol context reads it so, manager/webview.rs:229-233).
    # +headers+ is an array of [name, value] pairs with lowercase names,
    # and +body+ is a binary (ASCII-8BIT) String holding the exact request
    # bytes.
    #
    #   case event
    #   when Tokra::Native::HttpRequestEvent
    #     # Build Rack response...
    #     proxy.respond(event.request_id, 200, headers, body)
    #   end
    HttpRequestEvent = Data.define(:label, :request_id, :method, :uri, :headers, :body)

    # Page load event (started or finished) in the webview labeled +label+.
    #
    # Matches Tauri's +on_page_load+ API.
    #
    #   case event
    #   when Tokra::Native::PageLoadEvent
    #     puts "Page #{event.url} #{event.event} in #{event.label}"
    #     app.initialize_js if event.finished?
    #   end
    class PageLoadEvent < Data.define(:label, :event, :url)
      ##
      # Returns true if this is a page load started event.
      def started?
        event == "started"
      end

      ##
      # Returns true if this is a page load finished event.
      def finished?
        event == "finished"
      end
    end

    # Drag-drop event from the webview labeled +label+, which the App tells
    # the webview's window (tauri-runtime-wry lib.rs:4097-4122, 4695-4700).
    #
    # Matches Tauri's +DragDropEvent+ enum with Enter, Over, Drop, Leave variants.
    #
    #   case event
    #   when Tokra::Native::DragDropEvent
    #     case event.event
    #     when "enter" then handle_enter(event.paths, event.x, event.y)
    #     when "drop"  then handle_drop(event.paths, event.x, event.y)
    #     end
    #   end
    DragDropEvent = Data.define(:label, :event, :paths, :x, :y)

    # The native event loop is shutting down.
    #
    # Created from tao's LoopDestroyed event, the last event the loop
    # delivers before EventLoop#run raises SystemExit to end the process
    # with the loop's exit code. App turns it into
    # RunEvent::Exit, as Tauri's runtime does (tauri-runtime-wry lib.rs).
    #
    #   case event
    #   when Tokra::Native::LoopDestroyedEvent
    #     puts "event loop finished"
    #   end
    LoopDestroyedEvent = Data.define

    # A task is waiting to run on the main thread.
    #
    # Created once for each call another thread sends to the main thread
    # through Proxy#send_task. The App answers it by running the oldest
    # queued task (RuntimeContext#handle_task), as Tauri's runtime runs
    # Message::Task (tauri-runtime-wry lib.rs:3212).
    #
    #   case event
    #   when Tokra::Native::TaskEvent
    #     context.handle_task
    #   end
    TaskEvent = Data.define

    # A menu item was clicked: +id+ is the item's id, as muda's event
    # handler sent it through the loop (ext/tokra/src/menu.rs).
    MenuEvent = Data.define(:id)

    # The pointer acted on a tray icon, as tray-icon's event handler sent it
    # through the loop (ext/tokra/src/tray.rs): +kind+ names Tauri's
    # variant, +position+ is <tt>[x, y]</tt>, +rect+ is <tt>[x, y, width,
    # height]</tt>, and +button+ and +button_state+ are names or +nil+.
    TrayIconEvent = Data.define(:kind, :id, :position, :rect, :button, :button_state)
  end
end
