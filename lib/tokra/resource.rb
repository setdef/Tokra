# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2018-2023 the Deno authors, 2019-2024 Tauri Programme
# SPDX-SnippetComment: Resource trait adapted from tauri/crates/tauri/src/resources/mod.rs

module Tokra
  # Mixin for objects stored in ResourceTable.
  #
  # Resources are managed objects identified by integer IDs. They can be
  # stored in a ResourceTable and retrieved by their rid.
  #
  # This module provides default implementations for the resource protocol:
  # +name+:: returns the class name (for debugging)
  # +close+:: is a no-op (override for cleanup)
  #
  # Example:
  #   class MyResource
  #     include Tokra::Resource
  #
  #     def close
  #       # Custom cleanup logic
  #     end
  #   end
  #
  module Resource
    # Returns a string identifier for this resource.
    #
    # Default implementation returns the class name.
    # Override to provide a custom name for debugging.
    def name
      self.class.name || self.class.to_s
    end

    # Called when the resource is closed.
    #
    # Default implementation is a no-op.
    # Override to perform cleanup (e.g., releasing native handles).
    def close
      nil
    end
  end
end

# SPDX-SnippetEnd
