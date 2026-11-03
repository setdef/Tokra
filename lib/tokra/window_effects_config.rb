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
    # The configuration a command argument holds, as the derived
    # Deserialize reads it, with +deny_unknown_fields+: a map with any
    # other key is rejected. +effects+, a sequence of Effect names, is
    # required, and +state+, +radius+ (an +f64+), and +color+ (Color's
    # forms) are Options. A sequence form reads them in that order
    # (tauri-utils src/config.rs:1572-1588).
    def self.deserialize(value) # :nodoc:
      fields = Ipc::Serde.struct_fields(value, "WindowEffectsConfig", %w[effects state radius color],
        optional: %w[state radius color], deny_unknown: true) { |field, raw| field_value(field, raw) }
      effects = fields["effects"] #: Array[Effect]
      state = fields["state"] #: EffectState?
      radius = fields["radius"] #: Float?
      color = fields["color"] #: Color?
      new(effects:, state:, radius:, color:)
    end

    # The value of the field +name+ from +raw+.
    private_class_method def self.field_value(name, raw)
      case name
      when "effects"
        raise Ipc::CommandItem::Mismatch.invalid_type(raw, "a sequence") unless raw.is_a?(Array)

        raw.map { |effect| Effect.deserialize(effect) }
      when "state" then EffectState.deserialize(raw)
      when "radius" then Ipc::Serde.f64(raw)
      else Color.deserialize(raw)
      end
    end

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
