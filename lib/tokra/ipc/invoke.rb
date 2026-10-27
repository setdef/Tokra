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

      # What the frontend sent, as Tauri's <tt>InvokeMessage::payload</tt>
      # gives it (ipc/mod.rs:559-563): an InvokeBody. For the usual
      # <tt>invoke(cmd, { ... })</tt> it is a Hash with String keys:
      #
      #   invoke.payload["text"]  # => String
      #   invoke.payload["count"] # => Integer
      #
      # For an <tt>ArrayBuffer</tt> or typed array over <tt>ipc://</tt> it
      # is the bytes as a binary String, and for any other JSON value that
      # value, so check its type before indexing it, or read arguments with
      # CommandItem, which fails on such a body as Tauri does. The message
      # envelope's +cmd+, +callback+, and +error+ members stay with the
      # dispatcher.
      attr_reader :payload

      # The same InvokeBody as #payload, under the name Request gives it
      # (<tt>Request::body</tt>, ipc/mod.rs:154-157).
      def body
        @payload
      end

      # The request headers, as <tt>InvokeMessage::headers</tt>
      # (ipc/mod.rs:577-581): a frozen Hash of lowercase names to values.
      # Over <tt>ipc://</tt> they are all the request's headers, the page's
      # <tt>options.headers</tt> among them; over <tt>postMessage</tt> only
      # those.
      attr_reader :headers

      # The webview that made this IPC call.
      attr_reader :webview

      # Creates a new Invoke with command, payload, headers, webview, and
      # responder callback.
      #
      # This is called internally when dispatching IPC messages. +payload+
      # is the body, an InvokeBody, as <tt>InvokeMessage::new</tt> takes it
      # (ipc/mod.rs:526-541). The responder receives <tt>(success,
      # body)</tt>: whether the invoke resolved, and what each transport
      # puts on the wire, a binary String for raw bytes and JSON text
      # otherwise.
      def initialize(command:, payload:, responder:, webview:, headers: {})
        @command = command
        @payload = payload
        @headers = headers.frozen? ? headers : headers.dup.freeze
        @responder = responder
        @webview = webview
        @responded = false
      end

      # Resolves the invocation with a success value.
      #
      # An Ipc::Response sends its body as it is: raw bytes, or JSON text
      # (ipc/mod.rs:194-198). Any other value is serialized with
      # JSON.generate. Non-finite floats
      # (+NaN+, +Infinity+) become +null+, as serde_json writes them
      # (ser.rs:157-174). A value that still cannot be serialized, such as
      # a String holding invalid UTF-8 or an object whose +to_json+ raises,
      # rejects the invoke with the error's message instead, so the
      # frontend never waits forever. Only the first resolve or reject
      # reaches the frontend. Mirrors Tauri's InvokeResolver#resolve and its
      # InvokeResponse conversion (ipc/mod.rs:265-276, 404-406).
      #
      # === Example
      #
      #   invoke.resolve({ "greeting" => "Hello, #{invoke.payload['name']}!" })
      #   invoke.resolve(Tokra::Ipc::Response.new(File.binread(path)))
      def resolve(value)
        respond(true, value)
      end

      # Rejects the invocation with an error value.
      #
      # The frontend promise rejects with the value, usually a message
      # String. An unserializable value rejects with the serializer's
      # message instead, as Tauri's InvokeError conversion does
      # (ipc/mod.rs:240-247, 409-418). An Ipc::Response raises TypeError
      # and leaves the invoke unanswered: Tauri's reject takes a
      # <tt>T: Serialize</tt>, which Response is not, so Rust refuses it at
      # compile time.
      #
      # === Example
      #
      #   invoke.reject("Command greet needs a name")
      def reject(error)
        raise TypeError, "Tokra::Ipc::Response is not an invoke error" if error.is_a?(Response)

        respond(false, error)
      end

      # Serializes once and hands the body to the responder. The invoke is
      # marked responded only once the body exists, and any serialization
      # failure becomes a rejection, so every invoke settles exactly once.
      private def respond(success, value)
        return if @responded

        responder = @responder
        json = begin
          value.is_a?(Response) ? value.body : serialize(value)
        rescue => e
          success = false
          JSON.generate(e.message.dup.force_encoding(Encoding::UTF_8).scrub)
        end
        @responded = true
        responder&.call(success, json)
      end

      # JSON text for +value+. JSON.generate refuses non-finite floats, so a
      # value holding one is retried with them replaced by +nil+.
      private def serialize(value)
        JSON.generate(value)
      rescue JSON::GeneratorError
        finite = without_non_finite_floats(value)
        raise if finite == value

        JSON.generate(finite)
      end

      # +value+ with every NaN and Infinity inside it replaced by +nil+.
      private def without_non_finite_floats(value)
        case value
        when Float then value.finite? ? value : nil
        when Array then value.map { |item| without_non_finite_floats(item) }
        when Hash then value.transform_values { |item| without_non_finite_floats(item) }
        else value
        end
      end
    end
  end
end

# SPDX-SnippetEnd
