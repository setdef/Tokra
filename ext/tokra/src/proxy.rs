// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! Proxy wrapper for cross-Ractor communication.
//!
//! This module provides the Ruby-facing `Tokra::Native::Proxy` class,
//! which wraps `tao::event_loop::EventLoopProxy<UserEvent>`.
//!
//! The Proxy is the ONLY Tokra native type that is genuinely thread-safe
//! and Ractor-shareable, as `EventLoopProxy` is designed to be `Send+Sync`.

use magnus::{method, prelude::*, Error, Ruby};
use tao::event_loop::EventLoopProxy;

use crate::runtime_error;
use crate::user_event::UserEvent;

/// Ruby wrapper for `tao::event_loop::EventLoopProxy<UserEvent>`.
///
/// Thread-safe handle for waking up the event loop from Ractors.
/// This is the ONLY type that is genuinely designed to be Send+Sync safe by tao.
///
/// This type uses `frozen_shareable` to be Ractor-shareable when frozen.
/// Ruby automatically freezes objects shared across Ractors.
#[derive(Clone)]
pub struct RbProxy {
    inner: EventLoopProxy<UserEvent>,
}

impl RbProxy {
    /// Create a new `RbProxy` from an `EventLoopProxy`.
    #[must_use]
    pub const fn new(inner: EventLoopProxy<UserEvent>) -> Self {
        Self { inner }
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

    /// Send an HTTP response for a pending async protocol request.
    ///
    /// This is used by Ruby to respond to `tokra://` requests.
    /// The `request_id` must match a pending `HttpRequest` event.
    /// Headers should be an array of [name, value] pairs.
    ///
    /// # Thread Safety
    ///
    /// This is called directly from Ruby (potentially from a Ractor worker thread)
    /// and builds/sends the response immediately. This is safe because Wry's
    /// `RequestAsyncResponder` is `Send` and designed for cross-thread use.
    /// See: wry/src/lib.rs `unsafe impl Send for RequestAsyncResponder`
    ///
    /// # Errors
    ///
    /// Returns an error if the `request_id` is not found (already responded or invalid).
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
        body: String,
    ) -> Result<(), Error> {
        use crate::responders::get_responders;

        let responder = get_responders().lock().unwrap().remove(&request_id);
        match responder {
            Some(responder) => {
                let mut builder = wry::http::Response::builder().status(status);
                for (name, value) in &headers {
                    builder = builder.header(name, value);
                }
                let response = builder.body(body.into_bytes()).unwrap_or_else(|_| {
                    wry::http::Response::builder()
                        .status(500)
                        .body(b"Internal Error".to_vec())
                        .unwrap()
                });
                responder.respond(response);
                Ok(())
            }
            None => Err(Error::new(
                runtime_error(),
                format!("No pending request with id {request_id}"),
            )),
        }
    }
}

// RbProxy is genuinely Send+Sync because EventLoopProxy<T> is Send+Sync
// This is NOT an unsafe impl - tao guarantees this.
// SAFETY note: Sync is required for frozen_shareable in Magnus.
// EventLoopProxy is explicitly designed to be used from any thread.

impl magnus::DataTypeFunctions for RbProxy {}

// SAFETY: RbProxy wraps EventLoopProxy which is Send+Sync by design.
// This impl enables the frozen_shareable flag which makes the Ruby object
// Ractor-shareable when frozen. Ruby automatically freezes shareable objects.
#[allow(unsafe_code)]
unsafe impl magnus::TypedData for RbProxy {
    fn class(ruby: &magnus::Ruby) -> magnus::RClass {
        use magnus::Class;
        static CLASS: magnus::value::Lazy<magnus::RClass> = magnus::value::Lazy::new(|ruby| {
            let tokra = ruby.define_module("Tokra").unwrap();
            let native = tokra.define_module("Native").unwrap();
            let class = native.define_class("Proxy", ruby.class_object()).unwrap();
            class.undef_default_alloc_func();
            class
        });
        ruby.get_inner(&CLASS)
    }

    fn data_type() -> &'static magnus::DataType {
        static DATA_TYPE: magnus::DataType =
            magnus::typed_data::DataTypeBuilder::<RbProxy>::new(c"Tokra::Native::Proxy")
                .free_immediately()
                .size()
                .frozen_shareable()
                .build();
        &DATA_TYPE
    }
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
    proxy_class.define_method("respond", method!(RbProxy::respond, 4))?;
    Ok(())
}
