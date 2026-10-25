# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Tokra
  # Base error class for all Tokra errors.
  #
  # Error subclasses are nested under this class to mirror Tauri's
  # <tt>tauri::Error</tt> enum structure.
  #
  # Example:
  #   begin
  #     table.get(999)
  #   rescue Tokra::Error::BadResourceId => e
  #     puts "Invalid rid: #{e.rid}"
  #   end
  #
  class Error < StandardError
    # Raised when image bytes cannot be decoded.
    #
    # Mirrors <tt>tauri::Error::Image(ImageError)</tt>; the message keeps
    # Tauri's "failed to process image" prefix.
    class Image < Error
    end

    # SPDX-SnippetBegin
    # SPDX-License-Identifier: Apache-2.0 OR MIT
    # SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    # SPDX-SnippetComment: Runtime error and its messages from tauri/src/error.rs and
    # tauri-runtime/src/lib.rs

    # Raised when a call cannot reach the main thread, or its answer never
    # comes back.
    #
    # Window and webview calls made from another thread travel to the main
    # thread through the event loop. Once the loop has ended, a call cannot
    # get there, and a call already waiting for an answer will never get
    # one. Rescue this error in a background thread that may outlive the
    # loop.
    #
    # Mirrors <tt>tauri::Error::Runtime</tt>, whose message prefixes the
    # runtime error's own (error.rs:35-36), wrapping
    # <tt>FailedToSendMessage</tt> and <tt>FailedToReceiveMessage</tt>
    # (tauri-runtime lib.rs:131-136).
    #
    # === Example
    #
    #   Thread.new do
    #     window.title
    #   rescue Tokra::Error::Runtime => e
    #     e.message  #=> "runtime error: failed to send message to the webview"
    #   end
    class Runtime < Error
      # The message could not be sent to the main thread.
      FAILED_TO_SEND_MESSAGE = "failed to send message to the webview"

      # The main thread never answered.
      FAILED_TO_RECEIVE_MESSAGE = "failed to receive message from webview"

      # Creates a runtime error from the runtime's own +message+.
      def initialize(message)
        super("runtime error: #{message}")
      end
    end

    # SPDX-SnippetEnd

    # Raised when a resource ID is not found in a ResourceTable.
    #
    # Mirrors <tt>tauri::Error::BadResourceId(rid)</tt>.
    class BadResourceId < Error
      # The resource ID that was not found.
      attr_reader :rid

      # Creates a new BadResourceId error.
      #
      # +rid+:: the resource ID that was not found
      def initialize(rid)
        @rid = rid
        super("The resource id #{rid} is invalid.")
      end
    end
  end
end
