// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! Window wrapper for tao.
//!
//! This module provides the Ruby-facing `Tokra::Native::Window` class,
//! which wraps `tao::window::Window`.

use magnus::{function, method, prelude::*, Error, Ruby};
use tao::window::{Window, WindowBuilder};

use crate::event_loop::RbEventLoop;
use crate::runtime_error;

/// Ruby wrapper for `tao::window::Window`.
///
/// magnus wraps only `Send` types (`typed_data.rs:411-413`). tao declares its
/// `Window` `Send + Sync` on every desktop platform
/// (`platform_impl/macos/mod.rs:68-69`, `linux/window.rs:1056-1059`; on
/// Windows every field is), so this type needs no `unsafe impl` of its own.
#[magnus::wrap(class = "Tokra::Native::Window", free_immediately, size)]
pub struct RbWindow {
    pub(crate) inner: Window,
}

impl RbWindow {
    /// Create a new `Window` attached to the given `EventLoop`.
    ///
    /// # Errors
    ///
    /// Returns an error if the event loop has been consumed or window creation fails.
    pub fn new(event_loop: &RbEventLoop) -> Result<Self, Error> {
        let el = event_loop.inner.borrow();
        let el_ref = el.as_ref().ok_or_else(|| {
            Error::new(
                runtime_error(),
                "EventLoop has already been consumed by run()",
            )
        })?;

        let window = WindowBuilder::new()
            .with_title("Tokra")
            .build(el_ref)
            .map_err(|e| Error::new(runtime_error(), e.to_string()))?;

        Ok(Self { inner: window })
    }

    /// Set the window title.
    // Magnus FFI requires owned types at the Ruby-Rust boundary.
    // See clippy_exceptions.rb for justification.
    #[allow(clippy::needless_pass_by_value)]
    pub fn set_title(&self, title: String) {
        self.inner.set_title(&title);
    }

    /// Set the window inner size.
    pub fn set_size(&self, width: f64, height: f64) {
        use tao::dpi::LogicalSize;
        let size = LogicalSize::new(width, height);
        self.inner.set_inner_size(size);
    }

    /// Get the window ID as a string.
    #[must_use]
    pub fn id(&self) -> String {
        format!("{:?}", self.inner.id())
    }
}

/// Define the `Window` class methods on the given Ruby module.
///
/// # Errors
///
/// Returns an error if class or method definition fails.
pub fn define_class(ruby: &Ruby, native: magnus::RModule) -> Result<(), Error> {
    let window_class = native.define_class("Window", ruby.class_object())?;
    window_class.define_singleton_method("new", function!(RbWindow::new, 1))?;
    window_class.define_method("set_title", method!(RbWindow::set_title, 1))?;
    window_class.define_method("set_size", method!(RbWindow::set_size, 2))?;
    window_class.define_method("id", method!(RbWindow::id, 0))?;
    Ok(())
}
