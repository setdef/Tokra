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
