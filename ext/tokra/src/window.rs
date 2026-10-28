// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! Window wrapper for tao.
//!
//! This module provides the Ruby-facing `Tokra::Native::Window` class,
//! which wraps `tao::window::Window`.

use std::cell::{Ref, RefCell};

use magnus::{function, method, prelude::*, Error, RArray, Ruby};
use tao::event_loop::EventLoopProxy;
use tao::rwh_06::HasDisplayHandle;
use tao::window::{Window, WindowBuilder};

use crate::event_loop::RbEventLoop;
use crate::raw_handle;
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
    /// Empty once `close` has dropped the window.
    inner: RefCell<ThreadBound<Window>>,
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
        let inner = self.inner.get_mut();
        if !inner.owner().is_current() {
            let _ = self
                .proxy
                .send_event(UserEvent::Release(Released::Window(Box::new(inner.take()))));
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
            inner: RefCell::new(ThreadBound::new(window)),
            proxy: event_loop.proxy().clone(),
        })
    }

    /// The tao window, on the thread that created it, or `None` once
    /// `close` has dropped it.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` on any other thread, or a `RuntimeError` while
    /// `close` holds the window.
    pub(crate) fn open_window(&self) -> Result<Option<Ref<'_, Window>>, Error> {
        let inner = self
            .inner
            .try_borrow()
            .map_err(|_| Error::new(runtime_error(), "Window is closing"))?;
        if !inner.owner().is_current() {
            return Err(wrong_thread(CLASS));
        }
        Ok(Ref::filter_map(inner, ThreadBound::get).ok())
    }

    /// The tao window, on the thread that created it.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` on any other thread, or a `RuntimeError` once
    /// the window is closed.
    pub(crate) fn window(&self) -> Result<Ref<'_, Window>, Error> {
        self.open_window()?
            .ok_or_else(|| Error::new(runtime_error(), "Window is closed"))
    }

    // SPDX-SnippetBegin
    // SPDX-License-Identifier: Apache-2.0 OR MIT
    // SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    // SPDX-SnippetComment: Closing a window adapted from tauri-runtime-wry/src/lib.rs on_window_close
    /// Close the window by dropping it, as Tauri's `on_window_close` drops
    /// its `inner` window (tauri-runtime-wry `src/lib.rs:4293-4298`). tao
    /// closes a dropped window (`platform_impl/macos/window.rs:1734-1739`)
    /// and then reports `WindowEvent::Destroyed`. A closed window ignores
    /// its setters and answers `nil` for its title and id, as Tauri's
    /// runtime ignores a message for a window it no longer holds
    /// (`src/lib.rs:3244-3250`). Closing twice does nothing.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn close(&self) -> Result<(), Error> {
        let closed = {
            let mut inner = self
                .inner
                .try_borrow_mut()
                .map_err(|_| Error::new(runtime_error(), "Window is in use"))?;
            if !inner.owner().is_current() {
                return Err(wrong_thread(CLASS));
            }
            inner.take()
        };
        // Dropped here, on the owner's thread, after the borrow ends.
        drop(closed);
        Ok(())
    }
    // SPDX-SnippetEnd

    /// Set the window title.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    // Magnus FFI requires owned types at the Ruby-Rust boundary.
    // See clippy_exceptions.rb for justification.
    #[allow(clippy::needless_pass_by_value)]
    pub fn set_title(&self, title: String) -> Result<(), Error> {
        if let Some(window) = self.open_window()? {
            window.set_title(&title);
        }
        Ok(())
    }

    /// The window title.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn title(&self) -> Result<Option<String>, Error> {
        Ok(self.open_window()?.map(|window| window.title()))
    }

    /// Set the window inner size.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn set_size(&self, width: f64, height: f64) -> Result<(), Error> {
        use tao::dpi::LogicalSize;
        let size = LogicalSize::new(width, height);
        if let Some(window) = self.open_window()? {
            window.set_inner_size(size);
        }
        Ok(())
    }

    /// Set whether the window stays above every other window.
    ///
    /// tao puts it on `NSFloatingWindowLevel` on macOS, makes it topmost on
    /// Windows, and asks the X11 window manager to keep it above
    /// (`src/window.rs:1109-1119`, `platform_impl/macos/window.rs:1386-1393`).
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn set_always_on_top(&self, always_on_top: bool) -> Result<(), Error> {
        if let Some(window) = self.open_window()? {
            window.set_always_on_top(always_on_top);
        }
        Ok(())
    }

    /// Set whether the cursor's events pass through the window to whatever
    /// is behind it.
    ///
    /// tao answers `NotSupported` only on iOS and Android
    /// (`src/window.rs:1322-1333`), and tauri-runtime-wry drops its answer
    /// (`src/lib.rs:3461-3463`), so this has none.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn set_ignore_cursor_events(&self, ignore: bool) -> Result<(), Error> {
        if let Some(window) = self.open_window()? {
            let _ = window.set_ignore_cursor_events(ignore);
        }
        Ok(())
    }

    /// Get the window ID as a string.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn id(&self) -> Result<Option<String>, Error> {
        Ok(self
            .open_window()?
            .map(|window| format!("{:?}", window.id())))
    }

    /// The window's raw handle, as a tagged Array (`raw_handle.rs`), from
    /// tao's `HasWindowHandle` (tao 0.34.5 `src/window.rs:1422-1429`).
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn raw_window_handle(ruby: &Ruby, rb_self: &Self) -> Result<RArray, Error> {
        Ok(rb_self.open_window()?.map_or_else(
            || raw_handle::unavailable(ruby),
            |window| raw_handle::window_handle(ruby, &window),
        ))
    }

    /// The raw handle of the window's display, as a tagged Array
    /// (`raw_handle.rs`), from tao's `HasDisplayHandle` (tao 0.34.5
    /// `src/window.rs:1431-1437`).
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn raw_display_handle(ruby: &Ruby, rb_self: &Self) -> Result<RArray, Error> {
        let Some(window) = rb_self.open_window()? else {
            return Ok(raw_handle::unavailable(ruby));
        };
        Ok(raw_handle::display_handle(ruby, || {
            window.display_handle().map(|handle| handle.as_raw())
        }))
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
    window_class.define_method("set_always_on_top", method!(RbWindow::set_always_on_top, 1))?;
    window_class.define_method(
        "set_ignore_cursor_events",
        method!(RbWindow::set_ignore_cursor_events, 1),
    )?;
    window_class.define_method("id", method!(RbWindow::id, 0))?;
    window_class.define_method("close", method!(RbWindow::close, 0))?;
    window_class.define_method("raw_window_handle", method!(RbWindow::raw_window_handle, 0))?;
    window_class.define_method(
        "raw_display_handle",
        method!(RbWindow::raw_display_handle, 0),
    )?;
    crate::window_state::define_methods(window_class)
}
