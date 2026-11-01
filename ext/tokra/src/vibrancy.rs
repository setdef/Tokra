// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! Window effects (plan 045): Tauri's `vibrancy` module over the
//! window-vibrancy crate.
//!
//! Tauri's `Window::set_effects` runs `vibrancy::set_window_effects` on
//! the main thread and drops its result (`crates/tauri/src/window/mod.rs:1849-1855`).
//! The module applies the first effect in the list that the platform
//! has: an `NSVisualEffectMaterial` on macOS, Mica, Tabbed, Blur, or
//! Acrylic on Windows. Without a configuration it clears Windows'
//! effects and leaves macOS's. Linux has none. Ruby sends each effect,
//! and the state, by its `Tokra::Effect` or `Tokra::EffectState` name.

use magnus::{method, prelude::*, Error, RClass};

use crate::window::RbWindow;

/// A color as Ruby passes it: red, green, blue, and alpha.
type Rgba = (u8, u8, u8, u8);

/// A `WindowEffectsConfig` as Ruby passes it: the effects' names, the
/// state's name, the radius, and the color.
type Config = (Vec<String>, Option<String>, Option<f64>, Option<Rgba>);

// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: The effects and their platform materials adapted from
//                      tauri-utils/src/lib.rs and tauri/src/vibrancy/{mod,macos,windows}.rs

/// Every name `Tokra::Effect` has, in tauri-utils' order
/// (`src/lib.rs:68-139`).
const EFFECTS: [&str; 27] = [
    "AppearanceBased",
    "Light",
    "Dark",
    "MediumLight",
    "UltraDark",
    "Titlebar",
    "Selection",
    "Menu",
    "Popover",
    "Sidebar",
    "HeaderView",
    "Sheet",
    "WindowBackground",
    "HudWindow",
    "FullScreenUI",
    "Tooltip",
    "ContentBackground",
    "UnderWindowBackground",
    "UnderPageBackground",
    "Mica",
    "MicaDark",
    "MicaLight",
    "Tabbed",
    "TabbedDark",
    "TabbedLight",
    "Blur",
    "Acrylic",
];

/// Every name `Tokra::EffectState` has (`src/lib.rs:147-154`).
const STATES: [&str; 3] = ["FollowsWindowActiveState", "Active", "Inactive"];

/// An `ArgumentError` naming the first effect or state Ruby's classes do
/// not have, or `Ok` when every name is one of theirs.
fn check(effects: &[String], state: Option<&str>) -> Result<(), String> {
    if let Some(unknown) = effects
        .iter()
        .find(|name| !EFFECTS.contains(&name.as_str()))
    {
        return Err(format!("unknown effect: {unknown}"));
    }
    if let Some(unknown) = state.filter(|name| !STATES.contains(name)) {
        return Err(format!("unknown effect state: {unknown}"));
    }
    Ok(())
}

/// The macOS material for an effect, or `None` for another platform's
/// (`vibrancy/macos.rs:18-63`).
#[cfg(target_os = "macos")]
#[allow(deprecated)]
fn material(name: &str) -> Option<window_vibrancy::NSVisualEffectMaterial> {
    use window_vibrancy::NSVisualEffectMaterial as M;
    Some(match name {
        "AppearanceBased" => M::AppearanceBased,
        "Light" => M::Light,
        "Dark" => M::Dark,
        "MediumLight" => M::MediumLight,
        "UltraDark" => M::UltraDark,
        "Titlebar" => M::Titlebar,
        "Selection" => M::Selection,
        "Menu" => M::Menu,
        "Popover" => M::Popover,
        "Sidebar" => M::Sidebar,
        "HeaderView" => M::HeaderView,
        "Sheet" => M::Sheet,
        "WindowBackground" => M::WindowBackground,
        "HudWindow" => M::HudWindow,
        "FullScreenUI" => M::FullScreenUI,
        "Tooltip" => M::Tooltip,
        "ContentBackground" => M::ContentBackground,
        "UnderWindowBackground" => M::UnderWindowBackground,
        "UnderPageBackground" => M::UnderPageBackground,
        _ => return None,
    })
}

/// The macOS state for a `Tokra::EffectState` name (`vibrancy/macos.rs:72-76`).
#[cfg(target_os = "macos")]
fn effect_state(name: &str) -> window_vibrancy::NSVisualEffectState {
    use window_vibrancy::NSVisualEffectState as S;
    match name {
        "Active" => S::Active,
        "Inactive" => S::Inactive,
        _ => S::FollowsWindowActiveState,
    }
}

/// Applies the first macOS material among `effects`, or nothing
/// (`vibrancy/macos.rs:12-78`).
#[cfg(target_os = "macos")]
fn apply_effects(window: &tao::window::Window, (effects, state, radius, _color): Config) {
    let Some(effect) = effects.iter().find_map(|name| material(name)) else {
        return;
    };
    let _ =
        window_vibrancy::apply_vibrancy(window, effect, state.as_deref().map(effect_state), radius);
}

/// A Windows effect: Blur and Acrylic take the color; Mica and Tabbed
/// take whether to be dark, `None` to follow the system.
#[cfg(any(windows, test))]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum WindowsEffect {
    Blur,
    Acrylic,
    Mica(Option<bool>),
    Tabbed(Option<bool>),
}

/// The Windows effect an effect names, or `None` for another platform's
/// (`vibrancy/windows.rs:17-46`).
#[cfg(any(windows, test))]
fn windows_effect(name: &str) -> Option<WindowsEffect> {
    Some(match name {
        "Blur" => WindowsEffect::Blur,
        "Acrylic" => WindowsEffect::Acrylic,
        "Mica" => WindowsEffect::Mica(None),
        "MicaDark" => WindowsEffect::Mica(Some(true)),
        "MicaLight" => WindowsEffect::Mica(Some(false)),
        "Tabbed" => WindowsEffect::Tabbed(None),
        "TabbedDark" => WindowsEffect::Tabbed(Some(true)),
        "TabbedLight" => WindowsEffect::Tabbed(Some(false)),
        _ => return None,
    })
}

/// Applies the first Windows effect among `effects`, or nothing
/// (`vibrancy/windows.rs:16-47`).
#[cfg(windows)]
fn apply_effects(window: &tao::window::Window, (effects, _state, _radius, color): Config) {
    let Some(effect) = effects.iter().find_map(|name| windows_effect(name)) else {
        return;
    };
    let _ = match effect {
        WindowsEffect::Blur => window_vibrancy::apply_blur(window, color),
        WindowsEffect::Acrylic => window_vibrancy::apply_acrylic(window, color),
        WindowsEffect::Mica(dark) => window_vibrancy::apply_mica(window, dark),
        WindowsEffect::Tabbed(dark) => window_vibrancy::apply_tabbed(window, dark),
    };
}

/// Clears Windows' blur, acrylic, and mica (`vibrancy/windows.rs:49-53`).
#[cfg(windows)]
fn clear_effects(window: &tao::window::Window) {
    let _ = window_vibrancy::clear_blur(window);
    let _ = window_vibrancy::clear_acrylic(window);
    let _ = window_vibrancy::clear_mica(window);
}

/// Linux has no effects (`vibrancy/mod.rs:15-30`).
#[cfg(not(any(target_os = "macos", windows)))]
fn apply_effects(_window: &tao::window::Window, config: Config) {
    drop(config);
}

/// Only Windows clears effects (`vibrancy/mod.rs:25-28`).
#[cfg(not(windows))]
const fn clear_effects(_window: &tao::window::Window) {}

impl RbWindow {
    /// Tauri's `vibrancy::set_window_effects`: the configuration's first
    /// effect for this platform, or, for `nil`, Windows' effects cleared
    /// (`vibrancy/mod.rs:15-30`). Failures are dropped, as Tauri drops
    /// them (`window/mod.rs:1852`).
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread, or `ArgumentError`
    /// for an effect or state name Ruby's classes do not have.
    pub fn set_effects(&self, config: Option<Config>) -> Result<(), Error> {
        if let Some((effects, state, _, _)) = &config {
            check(effects, state.as_deref()).map_err(crate::window_state::argument_error)?;
        }
        if let Some(window) = self.open_window()? {
            match config {
                Some(config) => apply_effects(&window, config),
                None => clear_effects(&window),
            }
        }
        Ok(())
    }
}

// SPDX-SnippetEnd

/// Define `set_effects` on `Tokra::Native::Window`.
///
/// # Errors
///
/// Returns an error if method definition fails.
pub fn define_methods(class: RClass) -> Result<(), Error> {
    class.define_method("set_effects", method!(RbWindow::set_effects, 1))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn names(list: &[&str]) -> Vec<String> {
        list.iter().map(ToString::to_string).collect()
    }

    #[test]
    fn every_name_ruby_sends_passes_and_others_do_not() {
        assert_eq!(check(&names(&EFFECTS), Some("Active")), Ok(()));
        assert_eq!(
            check(&names(&["Mica", "Frosted"]), None),
            Err("unknown effect: Frosted".to_string())
        );
        assert_eq!(
            check(&names(&["Mica"]), Some("Sometimes")),
            Err("unknown effect state: Sometimes".to_string())
        );
    }

    #[test]
    fn windows_takes_the_first_of_its_own_effects() {
        let effects = names(&["Popover", "MicaDark", "Blur"]);
        assert_eq!(
            effects.iter().find_map(|name| windows_effect(name)),
            Some(WindowsEffect::Mica(Some(true)))
        );
        assert_eq!(
            names(&["Sidebar", "HudWindow"])
                .iter()
                .find_map(|name| windows_effect(name)),
            None
        );
        assert_eq!(
            windows_effect("TabbedLight"),
            Some(WindowsEffect::Tabbed(Some(false)))
        );
        assert_eq!(windows_effect("Acrylic"), Some(WindowsEffect::Acrylic));
    }

    #[cfg(target_os = "macos")]
    #[test]
    #[allow(deprecated)]
    fn macos_takes_the_first_of_its_own_materials() {
        use window_vibrancy::NSVisualEffectMaterial as M;
        let effects = names(&["Mica", "Popover", "Sidebar"]);
        assert_eq!(
            effects.iter().find_map(|name| material(name)),
            Some(M::Popover)
        );
        assert_eq!(material("UltraDark"), Some(M::UltraDark));
        assert_eq!(material("Acrylic"), None);
    }
}
