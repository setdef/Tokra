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
  # Invoke object for IPC commands.
  #
  # Passed to invoke_handler callbacks with command name and payload.
  # Use resolve/reject to respond to the frontend.
  class Invoke
    # The command name being invoked.
    attr_reader :command

    # The parsed JSON payload from the frontend (Hash with String keys).
    #
    # The framework parses the JSON message at dispatch time, matching Tauri's
    # <tt>InvokeBody::Json(serde_json::Value)</tt> semantics. Access values via string
    # keys:
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

# SPDX-SnippetEnd
