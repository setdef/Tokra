# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: InvokeBody adapted from tauri/crates/tauri/src/ipc/mod.rs

module Tokra
  module Ipc
    # What an invoke carried: a JSON value, or raw bytes.
    #
    # A page can invoke a command with an <tt>ArrayBuffer</tt> or a
    # <tt>Uint8Array</tt>, and the client sends those bytes as they are,
    # with no JSON around them. A command that takes a file's contents
    # needs to tell such a body from a JSON one, and a command that answers
    # with bytes needs to say so.
    #
    # Tauri's <tt>InvokeBody</tt> is an enum of <tt>Json(Value)</tt> and
    # <tt>Raw(Vec<u8>)</tt> (ipc/mod.rs:52-64). Ruby has one String class,
    # so Tokra stands a binary String, in <tt>Encoding::BINARY</tt>, for
    # Rust's <tt>Vec<u8></tt>, and any other value is JSON. Parsed JSON
    # strings are always UTF-8, so the two never meet. The same rule tells
    # an Ipc::Response of bytes from one of JSON text (Plan 033).
    #
    # === Example
    #
    #   body = Tokra::Ipc::Request.from_command(invoke).body
    #   File.binwrite(path, body) if Tokra::Ipc::InvokeBody.raw?(body)
    module InvokeBody
      # Whether +body+ is raw bytes, Tauri's <tt>InvokeBody::Raw</tt>: a
      # String in <tt>Encoding::BINARY</tt>.
      #
      # === Example
      #
      #   Tokra::Ipc::InvokeBody.raw?("\x01".b)  #=> true
      #   Tokra::Ipc::InvokeBody.raw?("text")    #=> false
      def self.raw?(body)
        body.is_a?(String) && body.encoding == Encoding::BINARY
      end
    end
  end
end

# SPDX-SnippetEnd
