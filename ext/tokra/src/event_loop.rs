// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! Event loop wrapper for tao.
//!
//! This module provides the Ruby-facing `Tokra::Native::EventLoop` class,
//! which wraps `tao::event_loop::EventLoop<UserEvent>`.

use std::cell::RefCell;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use magnus::{function, method, prelude::*, Error, Ruby, Value};
use tao::{
    event::{Event, WindowEvent},
    event_loop::{ControlFlow, EventLoop, EventLoopBuilder, EventLoopProxy},
};

use crate::proxy::RbProxy;
use crate::runtime_error;
use crate::user_event::UserEvent;

/// Ruby wrapper for `tao::event_loop::EventLoop<UserEvent>`.
///
/// The `EventLoop` owns the OS main thread and runs the window event pump.
#[magnus::wrap(class = "Tokra::Native::EventLoop", free_immediately, size)]
pub struct RbEventLoop {
    /// The inner event loop. Wrapped in Option because `run` consumes it.
    pub(crate) inner: RefCell<Option<EventLoop<UserEvent>>>,
    /// Proxy for creating `RbProxy` instances before `run()` consumes the loop.
    pub(crate) proxy: RefCell<Option<EventLoopProxy<UserEvent>>>,
}

// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2020-2023 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: Thread safety pattern adapted from tauri-runtime-wry/lib.rs unsafe impl Send for WindowsStore/DispatcherMainThreadContext

// SAFETY: RbEventLoop is only accessed from the main thread. The event loop
// itself runs on the main thread and all Ruby interactions happen there.
// This matches Tauri's pattern in tauri-runtime-wry.
// See clippy_exceptions.rb for full justification.
#[allow(unsafe_code)]
#[allow(clippy::non_send_fields_in_send_ty)]
unsafe impl Send for RbEventLoop {}

// SPDX-SnippetEnd

impl RbEventLoop {
    /// Create a new `EventLoop`.
    ///
    /// # Errors
    ///
    /// This function is infallible but returns `Result` for consistency with Magnus FFI.
    pub fn new() -> Result<Self, Error> {
        let event_loop = EventLoopBuilder::<UserEvent>::with_user_event().build();

        let proxy = event_loop.create_proxy();

        Ok(Self {
            inner: RefCell::new(Some(event_loop)),
            proxy: RefCell::new(Some(proxy)),
        })
    }

    /// Create a Proxy for cross-Ractor communication.
    ///
    /// Must be called before `run()` since run consumes the event loop.
    ///
    /// # Errors
    ///
    /// Returns an error if `run()` has already been called, consuming the event loop.
    pub fn create_proxy(&self) -> Result<RbProxy, Error> {
        let proxy = self.proxy.borrow().clone().ok_or_else(|| {
            Error::new(
                runtime_error(),
                "EventLoop has already been consumed by run()",
            )
        })?;

        Ok(RbProxy::new(proxy))
    }

    /// Run the event loop (blocking, never returns under normal operation).
    ///
    /// The callback Proc is invoked for each event.
    ///
    /// # Errors
    ///
    /// Returns an error if `run()` has already been called, consuming the event loop.
    ///
    /// # Panics
    ///
    /// Panics if the responders mutex is poisoned (internal invariant violation).
    pub fn run(&self, callback: Value) -> Result<(), Error> {
        let event_loop = self.inner.borrow_mut().take().ok_or_else(|| {
            Error::new(
                runtime_error(),
                "EventLoop has already been consumed by run()",
            )
        })?;

        // Setup ctrlc handler to send Exit event
        let proxy_for_ctrlc = self.proxy.borrow().clone();
        if let Some(proxy) = proxy_for_ctrlc {
            let exit_sent = Arc::new(AtomicBool::new(false));

            ctrlc::set_handler(move || {
                if !exit_sent.swap(true, Ordering::SeqCst) {
                    let _ = proxy.send_event(UserEvent::Exit);
                }
            })
            .ok(); // Ignore if already set
        }

        // Run the event loop - this is a blocking call
        event_loop.run(move |event, _, control_flow| {
            *control_flow = ControlFlow::Wait;

            // Helper to get Ruby class by constant path
            // Uses Ruby::get_with to safely get a Ruby handle from the callback value
            let get_ruby_class = |path: &str| -> Result<magnus::RClass, Error> {
                let ruby = Ruby::get_with(callback);
                ruby.eval(path)
                    .map_err(|e| Error::new(runtime_error(), format!("Failed to get {path}: {e}")))
            };

            match event {
                Event::UserEvent(user_event) => match user_event {
                    UserEvent::IpcMessage(msg) => {
                        if let Ok(klass) = get_ruby_class("::Tokra::Native::IpcEvent") {
                            // Data.define(:message) - pass positional arg
                            if let Ok(event_obj) = klass.funcall::<_, _, Value>("new", (msg,)) {
                                let _ = callback.funcall::<_, _, Value>("call", (event_obj,));
                            }
                        }
                    }
                    UserEvent::HttpRequest {
                        request_id,
                        method,
                        uri,
                        headers,
                        body,
                    } => {
                        if let Ok(klass) = get_ruby_class("::Tokra::Native::HttpRequestEvent") {
                            // Data.define(:request_id, :method, :uri, :headers, :body)
                            if let Ok(event_obj) = klass.funcall::<_, _, Value>(
                                "new",
                                (request_id, method, uri, headers, body),
                            ) {
                                let _ = callback.funcall::<_, _, Value>("call", (event_obj,));
                            }
                        }
                    }
                    UserEvent::PageLoad { event, url } => {
                        if let Ok(klass) = get_ruby_class("::Tokra::Native::PageLoadEvent") {
                            // Data.define(:event, :url)
                            if let Ok(event_obj) = klass.funcall::<_, _, Value>("new", (event, url))
                            {
                                let _ = callback.funcall::<_, _, Value>("call", (event_obj,));
                            }
                        }
                    }
                    UserEvent::DragDrop { event, paths, x, y } => {
                        if let Ok(klass) = get_ruby_class("::Tokra::Native::DragDropEvent") {
                            // Data.define(:event, :paths, :x, :y)
                            if let Ok(event_obj) =
                                klass.funcall::<_, _, Value>("new", (event, paths, x, y))
                            {
                                let _ = callback.funcall::<_, _, Value>("call", (event_obj,));
                            }
                        }
                    }
                    UserEvent::WakeUp(payload) => {
                        if let Ok(klass) = get_ruby_class("::Tokra::Native::WakeUpEvent") {
                            // Data.define(:payload)
                            if let Ok(event_obj) = klass.funcall::<_, _, Value>("new", (payload,)) {
                                let _ = callback.funcall::<_, _, Value>("call", (event_obj,));
                            }
                        }
                    }
                    UserEvent::Exit => {
                        *control_flow = ControlFlow::Exit;
                    }
                },
                Event::WindowEvent {
                    event: WindowEvent::CloseRequested,
                    ..
                } => {
                    // WindowCloseEvent has no fields
                    if let Ok(klass) = get_ruby_class("::Tokra::Native::WindowCloseEvent") {
                        if let Ok(event_obj) = klass.funcall::<_, _, Value>("new", ()) {
                            let _ = callback.funcall::<_, _, Value>("call", (event_obj,));
                        }
                    }
                    *control_flow = ControlFlow::Exit;
                }
                _ => {}
            }
        });
    }
}

/// Define the `EventLoop` class methods on the given Ruby module.
///
/// # Errors
///
/// Returns an error if class or method definition fails.
pub fn define_class(ruby: &Ruby, native: magnus::RModule) -> Result<(), Error> {
    let event_loop_class = native.define_class("EventLoop", ruby.class_object())?;
    event_loop_class.define_singleton_method("new", function!(RbEventLoop::new, 0))?;
    event_loop_class.define_method("create_proxy", method!(RbEventLoop::create_proxy, 0))?;
    event_loop_class.define_method("run", method!(RbEventLoop::run, 1))?;
    Ok(())
}
