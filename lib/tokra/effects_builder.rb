# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: EffectsBuilder adapted from tauri/src/window/mod.rs

module Tokra
  # Builds a WindowEffectsConfig one step at a time.
  #
  # Each method changes the builder and answers it, so calls chain; #build
  # answers the configuration. A step given the wrong type raises
  # TypeError when #build makes the configuration.
  #
  # Mirrors Tauri's <tt>tauri::window::EffectsBuilder</tt>
  # (window/mod.rs:2312-2365). Tauri's builder hands itself on from call
  # to call; this one changes itself, which chains the same way.
  #
  # === Example
  #
  #   config = Tokra::EffectsBuilder.new
  #     .effect(Tokra::Effect::Popover)
  #     .state(Tokra::EffectState::Active)
  #     .radius(5.0)
  #     .color(Tokra::Color.new(0, 0, 0, 255))
  #     .build
  #   window.set_effects(config)
  class EffectsBuilder
    # A builder that starts from +config+, a WindowEffectsConfig.
    #
    # Mirrors Tauri's <tt>From<WindowEffectsConfig> for EffectsBuilder</tt>
    # (window/mod.rs:2361-2365).
    #
    # === Example
    #
    #   Tokra::EffectsBuilder.from(config).effect(Tokra::Effect::Mica).build
    def self.from(config)
      raise TypeError, "wrong argument type #{config.class} (expected Tokra::WindowEffectsConfig)" unless config.is_a?(WindowEffectsConfig)

      builder = new
      builder.effects(config.effects)
      builder.state(config.state) if config.state
      builder.radius(config.radius) if config.radius
      builder.color(config.color) if config.color
      builder
    end

    # A builder with no effects, as WindowEffectsConfig's defaults.
    def initialize
      @effects = [] #: Array[Effect]
      @state = nil
      @radius = nil
      @color = nil
    end

    # Adds +effect+, an Effect, to the list.
    def effect(effect)
      @effects << effect
      self
    end

    # Adds each of +effects+, Effect values, to the list.
    def effects(effects)
      @effects.concat(effects.to_a)
      self
    end

    # Empties the list.
    def clear_effects
      @effects.clear
      self
    end

    # Sets the state, an EffectState. macOS only.
    def state(state)
      @state = state
      self
    end

    # Sets the corner radius, in points. macOS only.
    def radius(radius)
      @radius = radius
      self
    end

    # Sets the color, a Color. Windows only.
    def color(color)
      @color = color
      self
    end

    # The WindowEffectsConfig these steps describe.
    def build
      WindowEffectsConfig.new(effects: @effects.dup, state: @state, radius: @radius, color: @color)
    end
  end
end

# SPDX-SnippetEnd
