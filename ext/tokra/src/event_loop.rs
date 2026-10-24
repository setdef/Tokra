// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! Event loop wrapper for tao.
//!
//! This module provides the Ruby-facing `Tokra::Native::EventLoop` class,
//! which wraps `tao::event_loop::EventLoop<UserEvent>`.

use std::cell::RefCell;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use magnus::{
    error::ErrorType, function, kwargs, method, prelude::*, ArgList, Error, RClass, Ruby, Value,
};
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

            match event {
                Event::UserEvent(user_event) => match user_event {
                    UserEvent::IpcMessage { url, body } => {
                        // Data.define(:message, :url)
                        deliver(
                            callback,
                            "::Tokra::Native::IpcEvent",
                            (body, url),
                            control_flow,
                        );
                    }
                    UserEvent::HttpRequest {
                        request_id,
                        method,
                        uri,
                        headers,
                        body,
                    } => {
                        // Data.define(:request_id, :method, :uri, :headers, :body);
                        // the body arrives as a binary String holding the exact bytes.
                        let body = Ruby::get_with(callback).str_from_slice(&body);
                        deliver(
                            callback,
                            "::Tokra::Native::HttpRequestEvent",
                            (request_id, method, uri, headers, body),
                            control_flow,
                        );
                    }
                    UserEvent::PageLoad { event, url } => {
                        // Data.define(:event, :url)
                        deliver(
                            callback,
                            "::Tokra::Native::PageLoadEvent",
                            (event, url),
                            control_flow,
                        );
                    }
                    UserEvent::DragDrop { event, paths, x, y } => {
                        // Data.define(:event, :paths, :x, :y)
                        deliver(
                            callback,
                            "::Tokra::Native::DragDropEvent",
                            (event, paths, x, y),
                            control_flow,
                        );
                    }
                    UserEvent::WakeUp(payload) => {
                        // Data.define(:payload)
                        deliver(
                            callback,
                            "::Tokra::Native::WakeUpEvent",
                            (payload,),
                            control_flow,
                        );
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
                    deliver(
                        callback,
                        "::Tokra::Native::WindowCloseEvent",
                        (),
                        control_flow,
                    );
                    if *control_flow == ControlFlow::Wait {
                        *control_flow = ControlFlow::Exit;
                    }
                }
                // SPDX-SnippetBegin
                // SPDX-License-Identifier: Apache-2.0 OR MIT
                // SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
                // SPDX-SnippetComment: Exit on loop destruction adapted from tauri-runtime-wry/src/lib.rs handle_event_loop
                Event::LoopDestroyed => {
                    // tao calls process::exit right after this, so it is the
                    // last event Ruby sees; Tauri emits RunEvent::Exit from it.
                    deliver(
                        callback,
                        "::Tokra::Native::LoopDestroyedEvent",
                        (),
                        control_flow,
                    );
                }
                // SPDX-SnippetEnd
                _ => {}
            }
        });
    }
}

/// Build a `Tokra::Native` event and pass it to the Ruby callback.
///
/// The callback is the `App` dispatcher, and an exception it raises must not
/// vanish. A `SystemExit` (from `AppHandle#exit` or `Kernel#exit`) ends the
/// loop with its status. Any other exception is reported to stderr with its
/// full message and backtrace, and the loop keeps running, since one failed
/// event should not take down the window.
fn deliver<A: ArgList>(callback: Value, class_path: &str, args: A, control_flow: &mut ControlFlow) {
    let ruby = Ruby::get_with(callback);
    let result = ruby
        .eval::<RClass>(class_path)
        .and_then(|klass| klass.funcall::<_, _, Value>("new", args))
        .and_then(|event| callback.funcall::<_, _, Value>("call", (event,)));

    if let Err(error) = result {
        report_callback_error(&ruby, &error, control_flow);
    }
}

/// Handle an exception raised while delivering an event (see `deliver`).
fn report_callback_error(ruby: &Ruby, error: &Error, control_flow: &mut ControlFlow) {
    if let ErrorType::Exception(exception) = error.error_type() {
        if exception.is_kind_of(ruby.exception_system_exit()) {
            let status = exception.funcall::<_, _, i32>("status", ()).unwrap_or(1);
            *control_flow = ControlFlow::ExitWithCode(status);
            return;
        }
        let message = exception
            .funcall::<_, _, String>("full_message", (kwargs!("highlight" => false),))
            .unwrap_or_else(|_| error.to_string());
        warn(ruby, &message);
    } else {
        warn(ruby, &format!("Tokra event callback failed: {error}"));
    }
}

/// Write a message to Ruby's `$stderr` through `Kernel#warn`.
fn warn(ruby: &Ruby, message: &str) {
    if ruby
        .module_kernel()
        .funcall::<_, _, Value>("warn", (message,))
        .is_err()
    {
        eprintln!("{message}");
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
