// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! Proxy wrapper for cross-Ractor communication.
//!
//! This module provides the Ruby-facing `Tokra::Native::Proxy` class,
//! which wraps `tao::event_loop::EventLoopProxy<UserEvent>`.
//!
//! The Proxy is the ONLY Tokra native type that is genuinely thread-safe
//! and Ractor-shareable, as `EventLoopProxy` is designed to be `Send+Sync`.

use magnus::{method, prelude::*, Error, RString, Ruby};
use tao::event_loop::EventLoopProxy;

use crate::runtime_error;
use crate::thread_bound::OwnerThread;
use crate::user_event::{Answer, UserEvent};

/// Ruby wrapper for `tao::event_loop::EventLoopProxy<UserEvent>`.
///
/// Thread-safe handle for waking up the event loop from Ractors.
/// This is the ONLY type that is genuinely designed to be Send+Sync safe by tao.
///
/// This type uses `frozen_shareable` to be Ractor-shareable when frozen.
/// Ruby automatically freezes objects shared across Ractors. magnus accepts
/// the flag only for a `Sync` type (`typed_data.rs:384-395`), and
/// tao makes `EventLoopProxy` `Send + Sync` (`platform_impl/macos/event_loop.rs:307-308`,
/// `windows/event_loop.rs:558-559`; on Linux its one field, a crossbeam
/// `Sender`, is both), so the compiler checks the flag here.
#[magnus::wrap(
    class = "Tokra::Native::Proxy",
    free_immediately,
    size,
    frozen_shareable
)]
#[derive(Clone)]
pub struct RbProxy {
    inner: EventLoopProxy<UserEvent>,
    /// The thread that runs the loop, where custom-protocol answers go.
    loop_thread: OwnerThread,
}

impl RbProxy {
    /// Create a new `RbProxy` from an `EventLoopProxy` for the loop that
    /// runs on `loop_thread`.
    #[must_use]
    pub const fn new(inner: EventLoopProxy<UserEvent>, loop_thread: OwnerThread) -> Self {
        Self { inner, loop_thread }
    }

    /// Get a reference to the inner `EventLoopProxy`.
    #[must_use]
    pub const fn inner(&self) -> &EventLoopProxy<UserEvent> {
        &self.inner
    }

    /// Wake up the event loop with a payload.
    ///
    /// This is the critical method for Worker Ractor → Main Ractor communication.
    ///
    /// # Errors
    ///
    /// Returns an error if the event loop has been closed.
    pub fn wake_up(&self, payload: String) -> Result<(), Error> {
        self.inner
            .send_event(UserEvent::WakeUp(payload))
            .map_err(|_| {
                Error::new(
                    runtime_error(),
                    "Failed to send wake up event: event loop closed",
                )
            })
    }

    /// Wake the event loop to run one task `Tokra::RuntimeContext` queued.
    ///
    /// The loop delivers `Tokra::Native::TaskEvent` for it, and the App runs
    /// the oldest queued task on the main thread, as Tauri's runtime runs
    /// `Message::Task` (tauri-runtime-wry `src/lib.rs:3212`).
    ///
    /// # Errors
    ///
    /// Returns an error if the event loop has been closed.
    pub fn send_task(&self) -> Result<(), Error> {
        self.inner.send_event(UserEvent::Task).map_err(|_| {
            Error::new(
                runtime_error(),
                "Failed to send task event: event loop closed",
            )
        })
    }

    /// Send an HTTP response for a pending async protocol request.
    ///
    /// This is used by Ruby to respond to `tokra://` requests.
    /// The `request_id` must match a pending `HttpRequest` event.
    /// Headers should be an array of [name, value] pairs. The body is sent as
    /// its raw bytes whatever the Ruby string's encoding, so images, fonts,
    /// and other binary assets reach the `WebView` byte for byte.
    ///
    /// # Thread Safety
    ///
    /// Any thread may call it: wry's `RequestAsyncResponder` is `Send`. On
    /// the loop's thread it responds at once; on any other it sends the
    /// answer to the loop (see [`Answer`] for why).
    ///
    /// # Errors
    ///
    /// Returns an error if the `request_id` is not found (already responded
    /// or invalid), or if the answer must travel to an event loop that has
    /// closed.
    ///
    /// # Panics
    ///
    /// Panics if the responders mutex is poisoned (internal invariant violation).
    #[allow(clippy::needless_pass_by_value)] // Magnus FFI requires owned values
    #[allow(clippy::option_if_let_else)] // match is more readable here
    pub fn respond(
        &self,
        request_id: u64,
        status: u16,
        headers: Vec<(String, String)>,
        body: RString,
    ) -> Result<(), Error> {
        use crate::responders::{get_responders, take_responder};

        let body = body.to_bytes().to_vec();
        let responder = take_responder(get_responders(), request_id);
        match responder {
            Some(responder) => {
                let mut builder = wry::http::Response::builder().status(status);
                for (name, value) in &headers {
                    builder = builder.header(name, value);
                }
                let response = builder.body(body).unwrap_or_else(|_| {
                    wry::http::Response::builder()
                        .status(500)
                        .body(b"Internal Error".to_vec())
                        .unwrap()
                });
                self.answer(Answer {
                    responder,
                    response: Some(response),
                })
            }
            None => Err(Error::new(
                runtime_error(),
                format!("No pending request with id {request_id}"),
            )),
        }
    }

    // SPDX-SnippetBegin
    // SPDX-License-Identifier: Apache-2.0 OR MIT
    // SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    // SPDX-SnippetComment: Drop-without-reply behavior adapted from tauri/src/webview/mod.rs on_message key mismatch

    /// Drop a pending async protocol responder without replying.
    ///
    /// On an `ipc://` invoke-key mismatch, Tauri drops the owned responder by
    /// returning from `on_message`, which closes the response and makes the
    /// client `fetch` reject (webview/mod.rs). Tokra's responder lives in a map
    /// keyed by `request_id`, so the faithful equivalent is to remove and drop
    /// it. Unlike `respond`, a missing `request_id` is not an error: the drop is
    /// idempotent.
    ///
    /// # Panics
    ///
    /// Panics if the responders mutex is poisoned (internal invariant violation).
    ///
    /// # Errors
    ///
    /// Returns an error if the drop must travel to an event loop that has
    /// closed.
    pub fn drop_response(&self, request_id: u64) -> Result<(), Error> {
        use crate::responders::{get_responders, take_responder};

        take_responder(get_responders(), request_id).map_or(Ok(()), |responder| {
            self.answer(Answer {
                responder,
                response: None,
            })
        })
    }

    /// Deliver `answer` on the loop's thread: at once there, through the
    /// loop from anywhere else.
    ///
    /// If the loop has closed, the answer is forgotten rather than dropped
    /// here: its responder holds a `WebKit` task, and anything `WebKit` routes
    /// to the main run loop from this thread would wait forever for a loop
    /// that no longer runs.
    fn answer(&self, answer: Answer) -> Result<(), Error> {
        if self.loop_thread.is_current() {
            answer.deliver();
            return Ok(());
        }
        self.inner
            .send_event(UserEvent::Respond(answer))
            .map_err(|closed| {
                std::mem::forget(closed.0);
                Error::new(
                    runtime_error(),
                    "Failed to send response: event loop closed",
                )
            })
    }

    // SPDX-SnippetEnd
}

/// Define the `Proxy` class methods on the given Ruby module.
///
/// # Errors
///
/// Returns an error if class or method definition fails.
pub fn define_class(ruby: &Ruby, native: magnus::RModule) -> Result<(), Error> {
    use magnus::Class;
    let proxy_class = native.define_class("Proxy", ruby.class_object())?;
    // Prevent Ruby from allocating uninitialized Proxy objects
    // This fixes the "undefining the allocator of T_DATA class" warning
    proxy_class.undef_default_alloc_func();
    proxy_class.define_method("wake_up", method!(RbProxy::wake_up, 1))?;
    proxy_class.define_method("send_task", method!(RbProxy::send_task, 0))?;
    proxy_class.define_method("respond", method!(RbProxy::respond, 4))?;
    proxy_class.define_method("drop_response", method!(RbProxy::drop_response, 1))?;
    Ok(())
}
