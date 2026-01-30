// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

use magnus::{function, prelude::*, Error, Ruby};

/// Say hello from Rust!
#[allow(clippy::needless_pass_by_value)] // Magnus FFI requires owned types
fn hello(subject: String) -> String {
    format!("Hello from Rust, {subject}!")
}

/// Initialize the Tokra Ruby module.
///
/// # Errors
///
/// Returns an error if module or method definition fails.
#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let module = ruby.define_module("Tokra")?;
    module.define_singleton_method("hello", function!(hello, 1))?;
    Ok(())
}
