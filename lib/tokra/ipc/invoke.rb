# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Invoke adapted from tauri/crates/tauri/src/ipc/mod.rs

module Tokra
  # The inter-process communication layer between Ruby and the WebView.
  #
  # Mirrors Tauri's +ipc+ module (tauri/src/ipc/), which Tauri does not
  # re-export at the crate root; Tokra keeps the same shape.
  module Ipc
    # Invoke object for IPC commands.
    #
    # Passed to invoke_handler callbacks and plugin extend_api hooks with
    # the command name and payload. Use resolve/reject to respond to the
    # frontend: the responder delivers the value to the promise that the
    # frontend's <tt>invoke()</tt> call returned.
    class Invoke
      # The command name being invoked.
      #
      # For plugin commands, the router strips the
      # <tt>plugin:NAME|</tt> prefix before the plugin sees it.
      attr_reader :command

      # The command arguments from the frontend (Hash with String keys).
      #
      # This is the +payload+ member of the wire message, matching
      # Tauri's <tt>InvokeRequest#body</tt> (ipc/protocol.rs): the
      # message envelope's +cmd+, +callback+, and +error+ members stay
      # with the dispatcher. Access values via string keys:
      #
      #   invoke.payload["text"]  # => String
      #   invoke.payload["count"] # => Integer
      #
      attr_reader :payload

      # The webview that made this IPC call.
      attr_reader :webview

      # Creates a new Invoke with command, payload, webview, and responder callback.
      #
      # This is called internally when dispatching IPC messages.
      def initialize(command:, payload:, responder:, webview:)
        @command = command
        @payload = payload
        @responder = responder
        @webview = webview
        @responded = false
      end

      # Resolve the invocation with a success value.
      def resolve(value)
        return if @responded

        @responded = true
        @responder&.call(true, value)
      end

      # Reject the invocation with an error message.
      def reject(error)
        return if @responded

        @responded = true
        @responder&.call(false, error)
      end
    end
  end
end

# SPDX-SnippetEnd
