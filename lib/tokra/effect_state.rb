# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: EffectState adapted from tauri-utils/src/lib.rs (WindowEffectState)

module Tokra
  # Whether a macOS window effect looks active.
  #
  # macOS dims vibrancy in a window that is not in front, as it dims the
  # window's title. A panel that should always look alive, or never, picks
  # its state in WindowEffectsConfig. Only macOS reads it.
  #
  # These three are the only states, as in Tauri's enum, so
  # EffectState.new is private.
  #
  # Mirrors Tauri's <tt>tauri::window::EffectState</tt>, tauri-utils'
  # <tt>WindowEffectState</tt> (src/lib.rs:141-154), AppKit's
  # NSVisualEffectView state.
  #
  # === Example
  #
  #   Tokra::EffectsBuilder.new.effect(Tokra::Effect::Popover).state(Tokra::EffectState::Active).build
  class EffectState < Data.define(:name)
    extend ClosedEnum

    ##
    # The effect looks active while the window is.
    FollowsWindowActiveState = new(name: "FollowsWindowActiveState")
    # The effect always looks active.
    Active = new(name: "Active")
    # The effect never looks active.
    Inactive = new(name: "Inactive")

    # The states in Tauri's order, which serde's errors list.
    VARIANTS = [FollowsWindowActiveState, Active, Inactive].freeze
    private_constant :VARIANTS

    # The state a command argument names, as the derived Deserialize reads
    # it: a unit variant renamed camelCase, <tt>"followsWindowActiveState"</tt>
    # and so on (tauri-utils src/lib.rs:143-146; serde_derive
    # internals/case.rs:62).
    def self.deserialize(value) # :nodoc:
      states = VARIANTS.to_h { |state| [state.name.sub(/\A./, &:downcase), state] }
      states.fetch(Ipc::Serde.unit_variant(value, states.keys))
    end

    close
  end
end

# SPDX-SnippetEnd
