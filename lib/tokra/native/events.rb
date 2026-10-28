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
    # Created when JavaScript calls +window.ipc.postMessage()+. +message+
    # is the posted string; +url+ is the URL of the frame that posted it,
    # which wry reports as the request URI and Tauri treats as the invoke
    # origin (ipc/protocol.rs handle_ipc_message).
    #
    #   case event
    #   when Tokra::Native::IpcEvent
    #     puts "Received #{event.message} from #{event.url}"
    #   end
    IpcEvent = Data.define(:message, :url)

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

    # Window close requested.
    #
    # Created when the user clicks the window close button, or when
    # Proxy#request_close asks for the same. The loop keeps running: the
    # App asks its handlers and closes the native window unless one
    # prevents it (tauri-runtime-wry lib.rs:4262-4290).
    #
    #   case event
    #   when Tokra::Native::WindowCloseEvent
    #     window.close unless keep_open?
    #   end
    WindowCloseEvent = Data.define

    # The native window is gone.
    #
    # Created from tao's <tt>WindowEvent::Destroyed</tt>, which follows
    # Window#close. The callback's answer matters for this event: +true+
    # ends the loop with status 0, as the last window's exit request does
    # in Tauri's runtime (tauri-runtime-wry lib.rs:4171-4185); any other
    # answer keeps it running.
    #
    #   case event
    #   when Tokra::Native::WindowDestroyedEvent
    #     windows_left.empty?
    #   end
    WindowDestroyedEvent = Data.define

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
    # the async response via +proxy.respond()+. +headers+ is an array of
    # [name, value] pairs with lowercase names, and +body+ is a binary
    # (ASCII-8BIT) String holding the exact request bytes.
    #
    #   case event
    #   when Tokra::Native::HttpRequestEvent
    #     # Build Rack response...
    #     proxy.respond(event.request_id, 200, headers, body)
    #   end
    HttpRequestEvent = Data.define(:request_id, :method, :uri, :headers, :body)

    # Page load event (started or finished).
    #
    # Matches Tauri's +on_page_load+ API.
    #
    #   case event
    #   when Tokra::Native::PageLoadEvent
    #     puts "Page #{event.url} #{event.event}"
    #     app.initialize_js if event.finished?
    #   end
    class PageLoadEvent < Data.define(:event, :url)
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

    # Drag-drop event from webview.
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
    DragDropEvent = Data.define(:event, :paths, :x, :y)

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
  end
end
