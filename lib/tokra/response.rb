# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Response adapted from http crate patterns

module Tokra
  # HTTP response for URI scheme protocol handlers.
  #
  # Built and returned from protocol handler blocks.
  Response = Data.define(:status, :headers, :body) do
    # Create a 200 OK response with body.
    def self.ok(body, content_type: "text/html")
      new(status: 200, headers: { "content-type" => content_type }, body:)
    end

    # Create a 404 Not Found response.
    def self.not_found(message = "Not Found")
      new(status: 404, headers: { "content-type" => "text/plain" }, body: message)
    end

    # Create an error response with status code.
    def self.error(status, message)
      new(status:, headers: { "content-type" => "text/plain" }, body: message)
    end
  end
end

# SPDX-SnippetEnd
