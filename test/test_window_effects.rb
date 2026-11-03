# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "support/stub_native"
require_relative "support/test_app"

# Window effects (plan 045): Tauri's Effect, EffectState,
# WindowEffectsConfig, and EffectsBuilder, and Window#set_effects through
# a real AppHandle and the stub native window.
class TestWindowEffects < Minitest::Test
  def app_handle
    @app_handle ||= build_test_app.handle
  end

  def native
    @native ||= StubNative::Window.new(nil, "main")
  end

  def window
    @window ||= Tokra::Window.new(label: "win", native:, app_handle:)
  end

  # tauri-utils' WindowEffect (src/lib.rs:68-139) and WindowEffectState
  # (src/lib.rs:147-154).
  def test_the_effects_and_states_are_tauris
    effects = %w[
      AppearanceBased
      Light
      Dark
      MediumLight
      UltraDark
      Titlebar
      Selection
      Menu
      Popover
      Sidebar
      HeaderView
      Sheet
      WindowBackground
      HudWindow
      FullScreenUI
      Tooltip
      ContentBackground
      UnderWindowBackground
      UnderPageBackground
      Mica
      MicaDark
      MicaLight
      Tabbed
      TabbedDark
      TabbedLight
      Blur
      Acrylic
    ]
    assert_equal effects.sort, Tokra::Effect.constants.map { |name| Tokra::Effect.const_get(name).name }.sort
    assert_equal %w[Active FollowsWindowActiveState Inactive],
      Tokra::EffectState.constants.map { |name| Tokra::EffectState.const_get(name).name }.sort
  end

  # WindowEffectsConfig's Default (tauri-utils src/config.rs:1572-1588).
  def test_a_config_defaults_to_no_effects
    config = Tokra::WindowEffectsConfig.new

    assert_equal [], config.effects
    assert_nil config.state
    assert_nil config.radius
    assert_nil config.color
  end

  def test_a_config_keeps_a_radius_as_a_float_and_its_effects_frozen
    effects = [Tokra::Effect::Mica]
    config = Tokra::WindowEffectsConfig.new(effects:, radius: 5)

    assert_equal 5.0, config.radius
    assert_kind_of Float, config.radius
    effects << Tokra::Effect::Blur
    assert_equal [Tokra::Effect::Mica], config.effects
    assert_predicate config.effects, :frozen?
  end

  def test_a_config_field_of_the_wrong_type_raises_type_error
    assert_raises(TypeError) { Tokra::WindowEffectsConfig.new(effects: Tokra::Effect::Mica) }
    assert_raises(TypeError) { Tokra::WindowEffectsConfig.new(effects: ["Mica"]) }
    assert_raises(TypeError) { Tokra::WindowEffectsConfig.new(state: "Active") }
    assert_raises(TypeError) { Tokra::WindowEffectsConfig.new(radius: "5") }
    error = assert_raises(TypeError) { Tokra::WindowEffectsConfig.new(color: [0, 0, 0, 255]) }
    assert_equal "wrong argument type Array (expected Tokra::Color or nil)", error.message
  end

  # Tauri's EffectsBuilder (window/mod.rs:2312-2365).
  def test_the_builder_adds_clears_and_sets_each_field
    builder = Tokra::EffectsBuilder.new
    config = builder
      .effect(Tokra::Effect::Popover)
      .effects([Tokra::Effect::Mica, Tokra::Effect::Blur])
      .state(Tokra::EffectState::Active)
      .radius(5.0)
      .color(Tokra::Color.new(0, 0, 0, 255))
      .build

    assert_equal Tokra::WindowEffectsConfig.new(
      effects: [Tokra::Effect::Popover, Tokra::Effect::Mica, Tokra::Effect::Blur],
      state: Tokra::EffectState::Active,
      radius: 5.0,
      color: Tokra::Color.new(0, 0, 0, 255)
    ), config
    assert_equal [], builder.clear_effects.build.effects
    assert_equal 5.0, builder.build.radius, "clear_effects leaves the rest"
  end

  def test_a_builder_from_a_config_starts_with_its_fields
    config = Tokra::WindowEffectsConfig.new(effects: [Tokra::Effect::Sidebar], state: Tokra::EffectState::Inactive,
      radius: 2.0, color: Tokra::Color.new(1, 2, 3, 4))

    assert_equal config, Tokra::EffectsBuilder.from(config).build
    assert_equal [Tokra::Effect::Sidebar, Tokra::Effect::Mica],
      Tokra::EffectsBuilder.from(config).effect(Tokra::Effect::Mica).build.effects
    assert_raises(TypeError) { Tokra::EffectsBuilder.from(Tokra::EffectsBuilder.new) }
  end

  def test_a_builder_with_a_wrong_step_raises_type_error_when_it_builds
    assert_raises(TypeError) { Tokra::EffectsBuilder.new.state("Active").build }
  end

  # The vibrancy module picks the platform's effect in Rust, from the
  # names, state, radius, and color the window sends.
  def test_set_effects_sends_the_config_by_name
    config = Tokra::EffectsBuilder.new.effect(Tokra::Effect::HudWindow).effect(Tokra::Effect::Acrylic)
      .state(Tokra::EffectState::FollowsWindowActiveState).radius(8).color(Tokra::Color.new(9, 8, 7, 6)).build

    assert_nil window.set_effects(config)
    assert_equal [[%w[HudWindow Acrylic], "FollowsWindowActiveState", 8.0, [9, 8, 7, 6]]],
      native.requests[:set_effects]

    window.set_effects(Tokra::WindowEffectsConfig.new(effects: [Tokra::Effect::Mica]))
    assert_equal [[["Mica"], nil, nil, nil]], native.requests[:set_effects]
  end

  # Tauri's set_window_effects clears for None (vibrancy/mod.rs:15-30).
  def test_set_effects_nil_asks_to_clear
    assert_nil window.set_effects(nil)
    assert_equal [nil], native.requests[:set_effects]
  end

  def test_set_effects_takes_only_a_config
    assert_raises(TypeError) { window.set_effects(Tokra::EffectsBuilder.new) }
    refute native.requests.key?(:set_effects)
  end

  def test_a_closed_window_ignores_effects
    native.close

    window.set_effects(Tokra::WindowEffectsConfig.new(effects: [Tokra::Effect::Mica]))
    window.set_effects(nil)
    assert_empty native.requests
  end

  private def mismatch(&)
    assert_raises(Tokra::Ipc::CommandItem::Mismatch, &).message
  end

  # serde's names for WindowEffect, camelCase, in Tauri's order.
  EFFECT_NAMES = %w[
    appearanceBased
    light
    dark
    mediumLight
    ultraDark
    titlebar
    selection
    menu
    popover
    sidebar
    headerView
    sheet
    windowBackground
    hudWindow
    fullScreenUI
    tooltip
    contentBackground
    underWindowBackground
    underPageBackground
    mica
    micaDark
    micaLight
    tabbed
    tabbedDark
    tabbedLight
    blur
    acrylic
  ].freeze

  # Both enums derive Deserialize with rename_all = "camelCase"
  # (tauri-utils src/lib.rs:64-66, 143-146): serde_derive lowercases the
  # first letter (internals/case.rs:62).
  def test_effects_read_their_camel_case_names
    assert_same Tokra::Effect::HudWindow, Tokra::Effect.deserialize("hudWindow")
    assert_same Tokra::Effect::FullScreenUI, Tokra::Effect.deserialize("fullScreenUI")
    assert_same Tokra::Effect::Mica, Tokra::Effect.deserialize({ "mica" => nil })
    assert_equal EFFECT_NAMES.size, Tokra::Effect.constants.size
    EFFECT_NAMES.each do |name|
      assert_equal name, Tokra::Effect.deserialize(name).name.sub(/\A./, &:downcase)
    end
    assert_equal "unknown variant `HudWindow`, expected one of #{EFFECT_NAMES.map { |name| "`#{name}`" }.join(', ')}",
      mismatch { Tokra::Effect.deserialize("HudWindow") }
    assert_equal "invalid type: integer `1`, expected string or map", mismatch { Tokra::Effect.deserialize(1) }
  end

  def test_effect_states_read_their_camel_case_names
    assert_same Tokra::EffectState::FollowsWindowActiveState, Tokra::EffectState.deserialize("followsWindowActiveState")
    assert_same Tokra::EffectState::Active, Tokra::EffectState.deserialize("active")
    assert_same Tokra::EffectState::Inactive, Tokra::EffectState.deserialize("inactive")
    assert_equal "unknown variant `Active`, expected one of `followsWindowActiveState`, `active`, `inactive`",
      mismatch { Tokra::EffectState.deserialize("Active") }
  end

  # WindowEffectsConfig derives Deserialize with deny_unknown_fields, and
  # only +effects+ is not an Option (tauri-utils src/config.rs:1572-1588).
  def test_a_config_reads_its_fields_from_a_map_or_a_sequence
    config = Tokra::WindowEffectsConfig.deserialize(
      { "effects" => ["sidebar", "mica"], "state" => "active", "radius" => 12, "color" => [1, 2, 3] }
    )

    assert_equal Tokra::WindowEffectsConfig.new(effects: [Tokra::Effect::Sidebar, Tokra::Effect::Mica],
      state: Tokra::EffectState::Active, radius: 12.0, color: Tokra::Color.new(1, 2, 3, 255)), config
    assert_equal Tokra::WindowEffectsConfig.new, Tokra::WindowEffectsConfig.deserialize({ "effects" => [] })
    assert_equal Tokra::WindowEffectsConfig.new(effects: [Tokra::Effect::Blur], radius: 1.5),
      Tokra::WindowEffectsConfig.deserialize([["blur"], nil, 1.5, nil])
  end

  def test_a_config_rejects_in_serdes_words
    assert_equal "missing field `effects`", mismatch { Tokra::WindowEffectsConfig.deserialize({ "state" => "active" }) }
    assert_equal "unknown field `blur`, expected one of `effects`, `state`, `radius`, `color`",
      mismatch { Tokra::WindowEffectsConfig.deserialize({ "effects" => [], "blur" => true }) }
    assert_equal "invalid type: string \"mica\", expected a sequence",
      mismatch { Tokra::WindowEffectsConfig.deserialize({ "effects" => "mica" }) }
    assert_equal "invalid type: map, expected a sequence",
      mismatch { Tokra::WindowEffectsConfig.deserialize({ "effects" => { "mica" => nil } }) }
    assert_equal "unknown variant `Mica`, expected one of #{EFFECT_NAMES.map { |name| "`#{name}`" }.join(', ')}",
      mismatch { Tokra::WindowEffectsConfig.deserialize({ "effects" => ["Mica"] }) }
    assert_equal "invalid type: string \"1\", expected f64",
      mismatch { Tokra::WindowEffectsConfig.deserialize({ "effects" => [], "radius" => "1" }) }
    assert_equal "data did not match any variant of untagged enum InnerColor",
      mismatch { Tokra::WindowEffectsConfig.deserialize({ "effects" => [], "color" => [1] }) }
    assert_equal "invalid length 3, expected struct WindowEffectsConfig with 4 elements",
      mismatch { Tokra::WindowEffectsConfig.deserialize([[], nil, nil]) }
  end
end
