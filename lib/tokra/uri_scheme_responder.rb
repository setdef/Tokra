# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: UriSchemeResponder adapted from tauri/crates/tauri/src/ipc/protocol.rs

module Tokra
  ##
  # Single-use responder for async URI scheme protocol handlers.
  #
  # Ractor-shareable for use in worker Ractors. The response is sent
  # back to the main Ractor via a Port.
  #
  #   responder.respond(Tokra::Response.ok("hello"))
  #
  # Each responder can only be used once. Calling respond twice
  # raises an error.
  class UriSchemeResponder
    ##
    # The proxy used to send the response.
    attr_reader :port

    ##
    # The ID of the HTTP request this responder is for.
    attr_reader :request_id

    ##
    # Creates a new responder for the given request.
    def initialize(port:, request_id:)
      @port = port
      @request_id = request_id
      @responded = false
    end

    ##
    # Send a response for this request.
    def respond(response)
      raise Error, "already responded" if @responded

      @responded = true
      header_pairs = response.headers.map { |k, v| [k.to_s, v.to_s] } #: Array[[String, String]]
      port.respond(request_id, response.status, header_pairs, response.body)
    end
  end
end

# SPDX-SnippetEnd
