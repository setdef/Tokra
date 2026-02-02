// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! Native clipboard bindings for Tokra using arboard.
//!
//! This extension provides clipboard access that is Ractor-safe via
//! `frozen_shareable` and `rb_ext_ractor_safe(true)`.

use magnus::{function, method, prelude::*, Error, Ruby};
use std::sync::Mutex;

// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: Mutex<Option<Clipboard>> pattern and cleanup() method adapted from
// tauri-plugin-clipboard-manager/src/desktop.rs

/// Clipboard wrapper with internal Mutex for thread-safe access.
///
/// This struct wraps `arboard::Clipboard` in a `Mutex<Option<_>>` pattern
/// matching Tauri's implementation. The Mutex provides interior mutability
/// allowing methods to work on frozen (Ractor-shareable) objects.
pub struct RbClipboard {
    inner: Mutex<Option<arboard::Clipboard>>,
}

impl RbClipboard {
    fn new() -> Result<Self, Error> {
        arboard::Clipboard::new()
            .map(|c| Self {
                inner: Mutex::new(Some(c)),
            })
            .map_err(|e| {
                Error::new(
                    Ruby::get().unwrap().exception_runtime_error(),
                    e.to_string(),
                )
            })
    }

    fn read_text(&self) -> Result<Option<String>, Error> {
        let ruby = Ruby::get().unwrap();
        let mut guard = self.inner.lock().unwrap();
        match guard.as_mut() {
            Some(clipboard) => clipboard.get_text().map(Some).or_else(|e| match e {
                arboard::Error::ContentNotAvailable => Ok(None),
                _ => Err(Error::new(ruby.exception_runtime_error(), e.to_string())),
            }),
            None => Err(Error::new(
                ruby.exception_runtime_error(),
                "Clipboard has been cleaned up",
            )),
        }
    }

    fn write_text(&self, text: String) -> Result<(), Error> {
        let ruby = Ruby::get().unwrap();
        let mut guard = self.inner.lock().unwrap();
        match guard.as_mut() {
            Some(clipboard) => clipboard
                .set_text(text)
                .map_err(|e| Error::new(ruby.exception_runtime_error(), e.to_string())),
            None => Err(Error::new(
                ruby.exception_runtime_error(),
                "Clipboard has been cleaned up",
            )),
        }
    }

    fn clear(&self) -> Result<(), Error> {
        let ruby = Ruby::get().unwrap();
        let mut guard = self.inner.lock().unwrap();
        match guard.as_mut() {
            Some(clipboard) => clipboard
                .clear()
                .map_err(|e| Error::new(ruby.exception_runtime_error(), e.to_string())),
            None => Err(Error::new(
                ruby.exception_runtime_error(),
                "Clipboard has been cleaned up",
            )),
        }
    }

    fn cleanup(&self) {
        let mut guard = self.inner.lock().unwrap();
        guard.take(); // Drop the clipboard
    }
}

// SPDX-SnippetEnd

impl magnus::DataTypeFunctions for RbClipboard {}

// SAFETY: Mutex<Option<arboard::Clipboard>> is Send + Sync.
// arboard::Clipboard is Send + Sync on all platforms.
// This enables frozen_shareable for Ractor shareability.
#[allow(unsafe_code)]
unsafe impl magnus::TypedData for RbClipboard {
    fn class(ruby: &magnus::Ruby) -> magnus::RClass {
        use magnus::Class;
        static CLASS: magnus::value::Lazy<magnus::RClass> = magnus::value::Lazy::new(|ruby| {
            let module = ruby.define_module("TokraClipboard").unwrap();
            let native = module.define_module("Native").unwrap();
            let class = native
                .define_class("Clipboard", ruby.class_object())
                .unwrap();
            class.undef_default_alloc_func();
            class
        });
        ruby.get_inner(&CLASS)
    }

    fn data_type() -> &'static magnus::DataType {
        static DATA_TYPE: magnus::DataType =
            magnus::typed_data::DataTypeBuilder::<RbClipboard>::new(
                c"TokraClipboard::Native::Clipboard",
            )
            .free_immediately()
            .size()
            .frozen_shareable()
            .build();
        &DATA_TYPE
    }
}

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    use magnus::Class;

    // Mark this extension as Ractor-safe.
    // This allows methods to be called from non-main Ractors.
    // SAFETY: We ensure thread safety via Mutex<Option<Clipboard>>.
    #[allow(unsafe_code)]
    unsafe {
        rb_sys::rb_ext_ractor_safe(true);
    }

    let module = ruby.define_module("TokraClipboard")?;
    let native = module.define_module("Native")?;

    let clipboard_class = native.define_class("Clipboard", ruby.class_object())?;
    clipboard_class.undef_default_alloc_func();
    clipboard_class.define_singleton_method("new", function!(RbClipboard::new, 0))?;
    clipboard_class.define_method("read_text", method!(RbClipboard::read_text, 0))?;
    clipboard_class.define_method("write_text", method!(RbClipboard::write_text, 1))?;
    clipboard_class.define_method("clear", method!(RbClipboard::clear, 0))?;
    clipboard_class.define_method("cleanup", method!(RbClipboard::cleanup, 0))?;

    Ok(())
}
