// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! Native clipboard bindings for Tokra using arboard.
//!
//! This extension provides low-level clipboard access that is wrapped
//! by the `Tokra::Plugins::Clipboard` Ruby class.

use magnus::{function, prelude::*, Error, Ruby};

/// Read text from the system clipboard.
fn read_text(ruby: &Ruby) -> Result<Option<String>, Error> {
    Err(Error::new(
        ruby.exception_not_imp_error(),
        "read_text not yet implemented",
    ))
}

/// Write text to the system clipboard.
fn write_text(ruby: &Ruby, _text: String) -> Result<(), Error> {
    Err(Error::new(
        ruby.exception_not_imp_error(),
        "write_text not yet implemented",
    ))
}

/// Clear the clipboard contents.
fn clear(ruby: &Ruby) -> Result<(), Error> {
    Err(Error::new(
        ruby.exception_not_imp_error(),
        "clear not yet implemented",
    ))
}

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let module = ruby.define_module("TokraClipboard")?;
    let native = module.define_module("Native")?;

    native.define_singleton_method("read_text", function!(read_text, 0))?;
    native.define_singleton_method("write_text", function!(write_text, 1))?;
    native.define_singleton_method("clear", function!(clear, 0))?;

    Ok(())
}
