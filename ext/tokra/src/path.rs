// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! Path resolution bindings.
//!
//! Thin wrapper around the `dirs` crate. Exposes raw directory functions;
//! Ruby owns platform-specific path logic per ADR 005.

use magnus::{function, prelude::*, Error, Ruby};

/// Returns the user's home directory.
fn home_dir() -> Option<String> {
    dirs::home_dir().map(|p| p.to_string_lossy().into_owned())
}

/// Returns the user's local data directory.
///
/// - **Linux:** `~/.local/share`
/// - **macOS:** `~/Library/Application Support`
/// - **Windows:** `%LOCALAPPDATA%`
fn data_local_dir() -> Option<String> {
    dirs::data_local_dir().map(|p| p.to_string_lossy().into_owned())
}

/// Define path-related module functions on the Native module.
///
/// # Errors
///
/// Returns an error if function definition fails.
pub fn define_functions(_ruby: &Ruby, native: magnus::RModule) -> Result<(), Error> {
    native.define_singleton_method("home_dir", function!(home_dir, 0))?;
    native.define_singleton_method("data_local_dir", function!(data_local_dir, 0))?;
    Ok(())
}
