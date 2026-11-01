# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: WindowEffectsConfig adapted from tauri-utils/src/config.rs

module Tokra
  # The effects Window#set_effects applies, with how they look.
  #
  # +effects+ lists Effect values. Each platform applies the first one it
  # has and ignores the rest, so one list can name a macOS material and a
  # Windows one. +state+, an EffectState, and +radius+, the corner radius
  # in points, are read on macOS only. +color+, a Color, tints Blur and
  # Acrylic on Windows 10 v1903 and later, and does nothing on Windows 7
  # or 11. EffectsBuilder builds one a step at a time.
  #
  # Mirrors Tauri's <tt>WindowEffectsConfig</tt> (tauri-utils
  # src/config.rs:1572-1588). Each field defaults as Tauri's Default
  # does: no effects and +nil+. A field of another type raises TypeError,
  # where Rust would not compile.
  #
  # === Example
  #
  #   Tokra::WindowEffectsConfig.new(effects: [Tokra::Effect::HudWindow], radius: 12.0)
  class WindowEffectsConfig < Data.define(:effects, :state, :radius, :color)
    # Creates the configuration, raising TypeError for a field of the
    # wrong type. +radius+ may be any Real and is kept as a Float.
    # A Data class validating in initialize: its RBS declares self.new, as
    # AGENTS.md asks, and Steep cannot see that self.new reaches this.
    def initialize(effects: [], state: nil, radius: nil, color: nil) # steep:ignore MethodParameterMismatch
      raise TypeError, "wrong argument type #{effects.class} (expected Array)" unless effects.is_a?(Array)

      effects.each do |effect|
        raise TypeError, "wrong argument type #{effect.class} (expected Tokra::Effect)" unless effect.is_a?(Effect)
      end
      unless state.nil? || state.is_a?(EffectState)
        raise TypeError, "wrong argument type #{state.class} (expected Tokra::EffectState or nil)"
      end
      unless radius.nil? || radius.is_a?(Numeric)
        raise TypeError, "wrong argument type #{radius.class} (expected Float or nil)"
      end
      unless color.nil? || color.is_a?(Color)
        raise TypeError, "wrong argument type #{color.class} (expected Tokra::Color or nil)"
      end
      effects = effects.dup.freeze
      radius &&= Float(radius)
      super
    end
  end
end

# SPDX-SnippetEnd
