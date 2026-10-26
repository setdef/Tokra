// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! Window wrapper for tao.
//!
//! This module provides the Ruby-facing `Tokra::Native::Window` class,
//! which wraps `tao::window::Window`.

use magnus::{function, method, prelude::*, Error, Ruby};
use tao::event_loop::EventLoopProxy;
use tao::window::{Window, WindowBuilder};

use crate::event_loop::RbEventLoop;
use crate::runtime_error;
use crate::thread_bound::{wrong_thread, ThreadBound};
use crate::user_event::{Released, UserEvent};

/// The Ruby class name, for the wrong-thread error.
const CLASS: &str = "Tokra::Native::Window";

/// Ruby wrapper for `tao::window::Window`.
///
/// tao declares its `Window` `Send + Sync` (`platform_impl/macos/mod.rs:68-69`,
/// `linux/window.rs:1056-1059`), but that promise covers tao's own
/// dispatching, not Ruby's GVL. On macOS, tao runs most window work on the
/// main thread and makes the caller wait for it: dropping a window closes it
/// through `run_on_main`, which is `Queue::main().exec_sync`
/// (`platform_impl/macos/window.rs:1734-1739`, `util/async.rs:43-48`,
/// `242-249`). A Ruby thread that waits there holds the GVL, and the main
/// thread, waiting for the GVL in `Thread.pass`, never runs the queue. So the
/// window lives in a [`ThreadBound`] like the webview: every method answers
/// only the thread that created it, and a window Ruby frees on another
/// thread is sent to the loop and dropped on the main thread (see `Drop`).
/// Tauri, too, never calls a window off the main thread (`handle_user_message`'s
/// `Message::Window` arm, tauri-runtime-wry `src/lib.rs:3244`).
#[magnus::wrap(class = "Tokra::Native::Window", free_immediately, size)]
pub struct RbWindow {
    inner: ThreadBound<Window>,
    /// Carries the window back to its thread if Ruby frees this object on
    /// another (see `Drop`).
    proxy: EventLoopProxy<UserEvent>,
}

impl Drop for RbWindow {
    /// Drop the window on its own thread, as `RbWebView` drops its webview:
    /// off that thread the window travels to the loop (`UserEvent::Release`),
    /// and if the loop is gone the `ThreadBound` leaks it. No Ruby API is
    /// called, as `free_immediately` requires (magnus
    /// `src/typed_data.rs:310-316`).
    fn drop(&mut self) {
        if !self.inner.owner().is_current() {
            let _ = self
                .proxy
                .send_event(UserEvent::Release(Released::Window(Box::new(
                    self.inner.take(),
                ))));
        }
    }
}

impl RbWindow {
    /// Create a new `Window` attached to the given `EventLoop`.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the event loop's thread, or an error if the
    /// event loop has been consumed or window creation fails.
    pub fn new(event_loop: &RbEventLoop) -> Result<Self, Error> {
        let el = event_loop.loop_cell()?.borrow();
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

        Ok(Self {
            inner: ThreadBound::new(window),
            proxy: event_loop.proxy().clone(),
        })
    }

    /// The tao window, on the thread that created it.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` on any other thread.
    pub(crate) fn window(&self) -> Result<&Window, Error> {
        self.inner.get().ok_or_else(|| wrong_thread(CLASS))
    }

    /// Set the window title.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    // Magnus FFI requires owned types at the Ruby-Rust boundary.
    // See clippy_exceptions.rb for justification.
    #[allow(clippy::needless_pass_by_value)]
    pub fn set_title(&self, title: String) -> Result<(), Error> {
        self.window()?.set_title(&title);
        Ok(())
    }

    /// The window title.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn title(&self) -> Result<String, Error> {
        Ok(self.window()?.title())
    }

    /// Set the window inner size.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn set_size(&self, width: f64, height: f64) -> Result<(), Error> {
        use tao::dpi::LogicalSize;
        let size = LogicalSize::new(width, height);
        self.window()?.set_inner_size(size);
        Ok(())
    }

    /// Get the window ID as a string.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn id(&self) -> Result<String, Error> {
        Ok(format!("{:?}", self.window()?.id()))
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
    window_class.define_method("title", method!(RbWindow::title, 0))?;
    window_class.define_method("set_size", method!(RbWindow::set_size, 2))?;
    window_class.define_method("id", method!(RbWindow::id, 0))?;
    Ok(())
}
