# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2018-2023 the Deno authors, 2019-2024 Tauri Programme

require "securerandom"

module Tokra
  # Table for managing resources by integer ID.
  #
  # Resources are stored and retrieved by random u32 ID. Each Webview and
  # Window has its own ResourceTable. Full implementation in Phase 2.1.
  #
  # Ported from Deno's resource system via Tauri.
  class ResourceTable
    # Creates an empty resource table.
    def initialize
      @index = {}
    end

    # Checks if a resource ID exists in this table.
    #
    # This is a placeholder; Phase 2.1 adds add/get/take/close.
    def has?(rid)
      @index.key?(rid)
    end

    # Adds a resource to the table and returns its ID.
    #
    # +resource+:: the resource object to store
    #
    # Returns a random u32 integer ID.
    def add(resource)
      rid = next_rid
      @index[rid] = resource
      rid
    end

    # Retrieves a resource by ID.
    #
    # +rid+:: the resource ID to look up
    #
    # Raises Error::BadResourceId if the ID is not found.
    def get(rid)
      @index.fetch(rid) { raise Error::BadResourceId, rid }
    end

    # Removes a resource from the table and returns it.
    #
    # Unlike +close+, this does NOT call +close+ on the resource.
    #
    # +rid+:: the resource ID to remove
    #
    # Raises Error::BadResourceId if the ID is not found.
    def take(rid)
      resource = get(rid)
      @index.delete(rid)
      resource
    end

    # Removes a resource and calls +close+ on it.
    #
    # Resources must include the Resource module or otherwise respond to #close.
    #
    # +rid+:: the resource ID to close
    #
    # Raises Error::BadResourceId if the ID is not found.
    def close(rid)
      resource = take(rid)
      resource.close
      nil
    end

    # Replaces a resource at an existing ID.
    #
    # +rid+:: the resource ID to replace
    # +resource+:: the new resource to store
    #
    # Raises Error::BadResourceId if the ID is not found.
    def replace(rid, resource)
      raise Error::BadResourceId, rid unless @index.key?(rid)
      @index[rid] = resource
    end

    # Removes all resources from the table.
    #
    # Does NOT call +close+ on the resources.
    def clear
      @index.clear
    end

    # Yields each resource ID and name for debugging.
    #
    # Resources must include the Resource module or otherwise respond to #name.
    #
    # If no block is given, returns an Enumerator.
    def names
      return enum_for(:names) unless block_given?
      @index.each do |rid, resource|
        yield [rid, resource.name]
      end
    end

    private def next_rid
      loop do
        rid = SecureRandom.random_number(0xFFFF_FFFF)
        return rid unless @index.key?(rid)
      end
    end
  end
end

# SPDX-SnippetEnd
