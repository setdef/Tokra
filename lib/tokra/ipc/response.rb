# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Response adapted from tauri/crates/tauri/src/ipc/mod.rs

module Tokra
  module Ipc
    # An invoke result that is not serialized again.
    #
    # Invoke#resolve serializes its value as JSON. A command that answers
    # with bytes, such as one reading a file, should not pay for a JSON
    # number array, and the page should get an <tt>ArrayBuffer</tt>. A
    # command that already holds JSON text should not have it quoted.
    #
    # Resolve the invoke with a Response. A binary String body, in
    # <tt>Encoding::BINARY</tt>, is raw bytes: <tt>ipc://</tt> answers them
    # as <tt>application/octet-stream</tt> and the page's
    # <tt>invoke</tt> resolves to an <tt>ArrayBuffer</tt>. Over the
    # <tt>postMessage</tt> fallback the page gets them as an Array of
    # numbers, as Tauri sends them on macOS. Any other String is JSON text,
    # sent as it is, in UTF-8. Channel#send takes a Response too, and the
    # page's Channel receives its bytes as an <tt>ArrayBuffer</tt>, or as
    # an Array of numbers when a large message is fetched after the
    # client fell back to <tt>postMessage</tt>, as in Tauri.
    #
    # JSON text read as binary, from File.binread or a socket, is a binary
    # String too, so it would be sent as bytes: call
    # <tt>force_encoding(Encoding::UTF_8)</tt> on it first.
    #
    # Mirrors Tauri's <tt>ipc::Response</tt> (ipc/mod.rs:189-205), with
    # <tt>From<Vec<u8>></tt> and <tt>From<String></tt> told apart by the
    # String's encoding (InvokeBody). Tauri's <tt>From<InvokeBody></tt> is
    # not ported: a UTF-8 String body would read as JSON text (Plan 033).
    #
    # === Example
    #
    #   invoke.resolve(Tokra::Ipc::Response.new(File.binread(path)))
    class Response < Data.define(:body)
      # A response with +body+, a String: raw bytes when it is binary, JSON
      # text otherwise, encoded to UTF-8, since a Rust String is UTF-8 by
      # type (ipc/mod.rs:100-104). Raises TypeError for anything else, which
      # Rust's <tt>Into<InvokeResponseBody></tt> bound refuses at compile
      # time, ArgumentError for text that is not valid in its encoding, and
      # Encoding::UndefinedConversionError for text UTF-8 cannot hold.
      #
      # === Example
      #
      #   Tokra::Ipc::Response.new("\x01\x02".b)
      #   Tokra::Ipc::Response.new('{"ok":true}'.encode(Encoding::UTF_16LE)).body  #=> "{\"ok\":true}"
      def self.new(body)
        body = String.try_convert(body) || raise(TypeError, "no implicit conversion of #{body.class} into String")
        unless InvokeBody.raw?(body)
          raise ArgumentError, "invalid byte sequence in #{body.encoding}" unless body.valid_encoding?

          body = body.encode(Encoding::UTF_8)
        end
        super
      end

      # :attr_reader: body
      # The body Invoke#resolve sends, as <tt>IpcResponse::body</tt> gives
      # it (ipc/mod.rs:194-198).
    end
  end
end

# SPDX-SnippetEnd
