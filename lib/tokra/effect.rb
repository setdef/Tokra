# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Effect adapted from tauri-utils/src/lib.rs (WindowEffect)

module Tokra
  # A platform material a transparent window shows behind its content.
  #
  # A sidebar or a heads-up window looks native when the desktop shows
  # through it, blurred: macOS calls that vibrancy, Windows 11 Mica, and
  # Windows 10 acrylic. Each platform has its own set of materials. Name
  # the ones you want in a WindowEffectsConfig, the first for each
  # platform wins, and Window#set_effects applies it. Linux has none.
  #
  # These are the only effects, as in Tauri's enum, so Effect.new is
  # private. The first five are macOS materials Apple deprecated in macOS
  # 10.14 in favor of the semantic ones after them.
  #
  # Mirrors Tauri's <tt>tauri::window::Effect</tt>, tauri-utils'
  # <tt>WindowEffect</tt> (src/lib.rs:60-139).
  #
  # === Example
  #
  #   Tokra::EffectsBuilder.new.effect(Tokra::Effect::Sidebar).effect(Tokra::Effect::Mica).build
  class Effect < Data.define(:name)
    extend ClosedEnum

    ##
    # A default material for the view's appearance. macOS 10.14 and
    # earlier; choose a semantic material instead.
    AppearanceBased = new(name: "AppearanceBased")
    # macOS 10.14 and earlier; use a semantic material instead.
    Light = new(name: "Light")
    # macOS 10.14 and earlier; use a semantic material instead.
    Dark = new(name: "Dark")
    # macOS 10.14 and earlier; use a semantic material instead.
    MediumLight = new(name: "MediumLight")
    # macOS 10.14 and earlier; use a semantic material instead.
    UltraDark = new(name: "UltraDark")
    # macOS 10.10 and later.
    Titlebar = new(name: "Titlebar")
    # macOS 10.10 and later.
    Selection = new(name: "Selection")
    # macOS 10.11 and later.
    Menu = new(name: "Menu")
    # macOS 10.11 and later.
    Popover = new(name: "Popover")
    # macOS 10.11 and later.
    Sidebar = new(name: "Sidebar")
    # macOS 10.14 and later.
    HeaderView = new(name: "HeaderView")
    # macOS 10.14 and later.
    Sheet = new(name: "Sheet")
    # macOS 10.14 and later.
    WindowBackground = new(name: "WindowBackground")
    # macOS 10.14 and later.
    HudWindow = new(name: "HudWindow")
    # macOS 10.14 and later.
    FullScreenUI = new(name: "FullScreenUI")
    # macOS 10.14 and later.
    Tooltip = new(name: "Tooltip")
    # macOS 10.14 and later.
    ContentBackground = new(name: "ContentBackground")
    # macOS 10.14 and later.
    UnderWindowBackground = new(name: "UnderWindowBackground")
    # macOS 10.14 and later.
    UnderPageBackground = new(name: "UnderPageBackground")
    # Mica that follows the system's dark preference. Windows 11 only.
    Mica = new(name: "Mica")
    # Mica, dark when the system is dark. Windows 11 only.
    MicaDark = new(name: "MicaDark")
    # Mica, light. Windows 11 only.
    MicaLight = new(name: "MicaLight")
    # The tabbed material that follows the system's dark preference.
    # Windows 11 only.
    Tabbed = new(name: "Tabbed")
    # The tabbed material, dark when the system is dark. Windows 11 only.
    TabbedDark = new(name: "TabbedDark")
    # The tabbed material, light. Windows 11 only.
    TabbedLight = new(name: "TabbedLight")
    # Blur. Windows 7, 10, and 11 (22H1) only; it slows resizing and
    # dragging the window on Windows 11 build 22621.
    Blur = new(name: "Blur")
    # Acrylic. Windows 10 and 11 only; it slows resizing and dragging the
    # window on Windows 10 v1903 and later and Windows 11 build 22000.
    Acrylic = new(name: "Acrylic")

    # The effects in Tauri's order, which serde's errors list.
    VARIANTS = [
      AppearanceBased,
      Light,
      Dark,
      MediumLight,
      UltraDark,
      Titlebar,
      Selection,
      Menu,
      Popover,
      Sidebar,
      HeaderView,
      Sheet,
      WindowBackground,
      HudWindow,
      FullScreenUI,
      Tooltip,
      ContentBackground,
      UnderWindowBackground,
      UnderPageBackground,
      Mica,
      MicaDark,
      MicaLight,
      Tabbed,
      TabbedDark,
      TabbedLight,
      Blur,
      Acrylic,
    ].freeze
    private_constant :VARIANTS

    # The effect a command argument names, as the derived Deserialize
    # reads it: a unit variant renamed camelCase, <tt>"hudWindow"</tt> and
    # so on (tauri-utils src/lib.rs:64-66; serde_derive
    # internals/case.rs:62).
    def self.deserialize(value) # :nodoc:
      effects = VARIANTS.to_h { |effect| [effect.name.sub(/\A./, &:downcase), effect] }
      effects.fetch(Ipc::Serde.unit_variant(value, effects.keys))
    end

    close
  end
end

# SPDX-SnippetEnd
