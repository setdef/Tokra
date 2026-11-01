// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! The taskbar and the title bar (plan 045): the progress bar, badges, the
//! overlay icon, and the macOS title bar style.
//!
//! Each method is what tauri-runtime-wry's `handle_user_message` does for
//! the matching `WindowMessage` (`src/lib.rs:3482-3534`), on the main
//! thread. A closed window ignores each, as plan 040's setters do.

use magnus::{method, prelude::*, Error, RClass, RString};
use tao::window::{ProgressBarState, ProgressState};

use crate::window::RbWindow;
use crate::window_state::argument_error;

// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: The taskbar and title bar messages adapted from tauri-runtime-wry/src/lib.rs

/// tao's progress state for a `Tokra::ProgressBarStatus` name, as
/// `ProgressStateWrapper` maps Tauri's (`src/lib.rs:755-768`).
fn progress_state(name: &str) -> Result<ProgressState, String> {
    Ok(match name {
        "None" => ProgressState::None,
        "Normal" => ProgressState::Normal,
        "Indeterminate" => ProgressState::Indeterminate,
        "Paused" => ProgressState::Paused,
        "Error" => ProgressState::Error,
        other => return Err(format!("unknown progress bar status: {other}")),
    })
}

/// Whether the title bar is transparent and the content view fills the
/// window, for a `Tokra::TitleBarStyle` name (`src/lib.rs:3511-3534`).
fn title_bar(name: &str) -> Result<(bool, bool), String> {
    Ok(match name {
        "Visible" => (false, true),
        "Transparent" => (true, false),
        "Overlay" => (true, true),
        other => return Err(format!("unknown title bar style: {other}")),
    })
}

impl RbWindow {
    /// tao's `Window::set_progress_bar`, as `ProgressBarStateWrapper`
    /// builds its state (`src/lib.rs:770-782`, `3508-3510`).
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread, or `ArgumentError`
    /// for a name `Tokra::ProgressBarStatus` does not have.
    pub fn set_progress_bar(
        &self,
        status: Option<RString>,
        progress: Option<u64>,
        desktop_filename: Option<RString>,
    ) -> Result<(), Error> {
        let status = status.map(RString::to_string).transpose()?;
        let desktop_filename = desktop_filename.map(RString::to_string).transpose()?;
        let state = status
            .as_deref()
            .map(progress_state)
            .transpose()
            .map_err(argument_error)?;
        if let Some(window) = self.open_window()? {
            window.set_progress_bar(ProgressBarState {
                state,
                progress,
                desktop_filename,
            });
        }
        Ok(())
    }

    /// The badge count: on macOS the count as the Dock tile's label, on
    /// Linux tao's Unity badge, on Windows nothing (`src/lib.rs:3482-3499`).
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn set_badge_count(
        &self,
        count: Option<i64>,
        desktop_filename: Option<RString>,
    ) -> Result<(), Error> {
        if let Some(window) = self.open_window()? {
            #[cfg(target_os = "macos")]
            {
                use tao::platform::macos::WindowExtMacOS;
                let _ = desktop_filename;
                window.set_badge_label(count.map(|count| count.to_string()));
            }
            #[cfg(any(
                target_os = "linux",
                target_os = "dragonfly",
                target_os = "freebsd",
                target_os = "netbsd",
                target_os = "openbsd"
            ))]
            {
                use tao::platform::unix::WindowExtUnix;
                let desktop_filename = desktop_filename.map(RString::to_string).transpose()?;
                window.set_badge_count(count, desktop_filename);
            }
            #[cfg(windows)]
            let _ = (&window, count, desktop_filename);
        }
        Ok(())
    }

    /// The Dock tile's badge label (`src/lib.rs:3500-3503`).
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    #[cfg(target_os = "macos")]
    pub fn set_badge_label(&self, label: Option<String>) -> Result<(), Error> {
        use tao::platform::macos::WindowExtMacOS;
        if let Some(window) = self.open_window()? {
            window.set_badge_label(label);
        }
        Ok(())
    }

    /// The taskbar button's overlay icon, `nil` to take it away
    /// (`src/lib.rs:3504-3507`). Tauri drops its icon once the call
    /// returns, and so does this, so the Ruby object may go then.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    #[cfg(windows)]
    pub fn set_overlay_icon(&self, icon: Option<&crate::icon::RbIcon>) -> Result<(), Error> {
        use tao::platform::windows::WindowExtWindows;
        if let Some(window) = self.open_window()? {
            let icon = icon.map(crate::icon::RbIcon::icon);
            window.set_overlay_icon(icon.as_ref());
        }
        Ok(())
    }

    /// The macOS title bar style; nothing elsewhere (`src/lib.rs:3511-3534`).
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread, or `ArgumentError`
    /// for a name `Tokra::TitleBarStyle` does not have.
    pub fn set_title_bar_style(&self, name: RString) -> Result<(), Error> {
        let (transparent, fullsize) = title_bar(&name.to_string()?).map_err(argument_error)?;
        if let Some(window) = self.open_window()? {
            #[cfg(target_os = "macos")]
            {
                use tao::platform::macos::WindowExtMacOS;
                window.set_titlebar_transparent(transparent);
                window.set_fullsize_content_view(fullsize);
            }
            #[cfg(not(target_os = "macos"))]
            let _ = (&window, transparent, fullsize);
        }
        Ok(())
    }
}

// SPDX-SnippetEnd

/// Define the taskbar and title bar setters on `Tokra::Native::Window`;
/// `set_badge_label` only on macOS and `set_overlay_icon` only on
/// Windows, as Tauri compiles them (`window/mod.rs:2113-2149`).
///
/// # Errors
///
/// Returns an error if method definition fails.
pub fn define_methods(class: RClass) -> Result<(), Error> {
    class.define_method("set_progress_bar", method!(RbWindow::set_progress_bar, 3))?;
    class.define_method("set_badge_count", method!(RbWindow::set_badge_count, 2))?;
    #[cfg(target_os = "macos")]
    class.define_method("set_badge_label", method!(RbWindow::set_badge_label, 1))?;
    #[cfg(windows)]
    class.define_method("set_overlay_icon", method!(RbWindow::set_overlay_icon, 1))?;
    class.define_method(
        "set_title_bar_style",
        method!(RbWindow::set_title_bar_style, 1),
    )?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn each_title_bar_style_is_tauris_pair() {
        assert_eq!(title_bar("Visible"), Ok((false, true)));
        assert_eq!(title_bar("Transparent"), Ok((true, false)));
        assert_eq!(title_bar("Overlay"), Ok((true, true)));
        assert_eq!(
            title_bar("Hidden"),
            Err("unknown title bar style: Hidden".to_string())
        );
    }

    #[test]
    fn each_status_is_taos_state() {
        assert!(matches!(progress_state("None"), Ok(ProgressState::None)));
        assert!(matches!(
            progress_state("Paused"),
            Ok(ProgressState::Paused)
        ));
        assert!(matches!(progress_state("Error"), Ok(ProgressState::Error)));
        assert_eq!(
            progress_state("Done").err(),
            Some("unknown progress bar status: Done".to_string())
        );
    }
}
