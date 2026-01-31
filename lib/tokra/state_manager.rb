# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: StateManager adapted from tauri/crates/tauri/src/state.rs

module Tokra
  # Manages application state by type.
  #
  # State is stored in a class-keyed hash, allowing one instance per class.
  # This exists because Ractor blocks cannot capture outer variables -
  # state must be registered at build-time and looked up explicitly at runtime.
  class StateManager
    # Creates a new StateManager with an empty state map.
    def initialize
      @map = {}
    end

    # Stores state by its class.
    #
    # Returns +true+ if state was stored, +false+ if already present.
    def set(state)
      return false if @map.key?(state.class)

      @map[state.class] = state
      true
    end

    # Retrieves state by class.
    #
    # Raises +KeyError+ if not found.
    def get(klass)
      @map.fetch(klass)
    end

    # Retrieves state by class, or +nil+ if not found.
    def try_get(klass)
      @map[klass]
    end
  end
end

# SPDX-SnippetEnd
