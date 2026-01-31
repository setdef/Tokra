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
    # Created when JavaScript calls +window.ipc.postMessage()+.
    #
    #   case event
    #   when Tokra::Native::IpcEvent
    #     puts "Received: #{event.message}"
    #   end
    IpcEvent = Data.define(:message)

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
    # Created when the user clicks the window close button.
    # The event loop will exit after dispatching this event.
    WindowCloseEvent = Data.define

    # HTTP request from WebView via the +tokra://+ custom protocol.
    #
    # Contains all request data including a +request_id+ for correlating
    # the async response via +proxy.respond()+.
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
  end
end
