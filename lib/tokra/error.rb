# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Tokra
  # Base error class for all Tokra errors.
  #
  # Error subclasses are nested under this class to mirror Tauri's
  # +tauri::Error+ enum structure.
  #
  # Example:
  #   begin
  #     table.get(999)
  #   rescue Tokra::Error::BadResourceId => e
  #     puts "Invalid rid: #{e.rid}"
  #   end
  #
  class Error < StandardError
    # Raised when a resource ID is not found in a ResourceTable.
    #
    # Mirrors +tauri::Error::BadResourceId(rid)+.
    class BadResourceId < Error
      # The resource ID that was not found.
      attr_reader :rid

      # Creates a new BadResourceId error.
      #
      # +rid+:: the resource ID that was not found
      def initialize(rid)
        @rid = rid
        super("Resource ID #{rid} not found")
      end
    end
  end
end
