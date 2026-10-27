# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Request adapted from tauri/crates/tauri/src/ipc/mod.rs

module Tokra
  module Ipc
    # The body and headers of an invoke, for a command that reads them
    # whole.
    #
    # Most commands take named arguments, which CommandItem reads. A
    # command that takes bytes, such as one writing a file, takes the
    # whole body instead, and reads anything else it needs from the
    # headers the page passed in <tt>invoke(cmd, bytes, { headers })</tt>.
    #
    # Mirrors Tauri's <tt>ipc::Request</tt> (ipc/mod.rs:143-171). +body+ is
    # an InvokeBody: a binary String when the page sent an
    # <tt>ArrayBuffer</tt> or typed array over <tt>ipc://</tt>, and
    # otherwise the JSON value, so a typed array sent over the
    # <tt>postMessage</tt> fallback arrives as an Array of Integers.
    # +headers+ is a frozen Hash of lowercase header names to values: on
    # <tt>ipc://</tt> every request header, on <tt>postMessage</tt> the
    # page's <tt>options.headers</tt>.
    #
    # === Example
    #
    #   request = Tokra::Ipc::Request.from_command(invoke)
    #   path = request.headers["path"]
    #   bytes = Tokra::Ipc::InvokeBody.raw?(request.body) ? request.body : request.body.pack("C*")
    class Request < Data.define(:body, :headers)
      # The request of +invoke+, as the CommandArg impl for Request reads
      # it (ipc/mod.rs:164-171).
      #
      # === Example
      #
      #   Tokra::Ipc::Request.from_command(invoke).body  #=> "\x89PNG..."
      def self.from_command(invoke)
        new(body: invoke.body, headers: invoke.headers)
      end

      # :attr_reader: body
      # The request body, an InvokeBody, as <tt>Request::body</tt>.

      # :attr_reader: headers
      # The request headers, as <tt>Request::headers</tt>: a frozen Hash of
      # lowercase names to values.
    end
  end
end

# SPDX-SnippetEnd
