// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! `WebView` wrapper for wry.
//!
//! This module provides the Ruby-facing `Tokra::Native::WebView` class,
//! which wraps `wry::WebView` and implements the tokra:// custom protocol.

use magnus::{function, method, prelude::*, Error, Ruby, Value};
use wry::{PageLoadEvent, WebView, WebViewBuilder};

use crate::proxy::RbProxy;
use crate::responders::{get_responders, next_request_id};
use crate::runtime_error;
use crate::user_event::UserEvent;
use crate::window::RbWindow;

/// Ruby wrapper for `wry::WebView`.
#[magnus::wrap(class = "Tokra::Native::WebView", free_immediately, size)]
pub struct RbWebView {
    inner: WebView,
}

// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2020-2023 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: Thread safety pattern adapted from tauri-runtime-wry/lib.rs unsafe impl Send for WindowsStore

// SAFETY: RbWebView is only accessed from the main thread. WebView operations
// are only performed within the event loop callback on the main thread.
// This matches Tauri's pattern in tauri-runtime-wry where they use:
// `unsafe impl Send for WindowsStore {}` with the comment:
// "SAFETY: we ensure this type is only used on the main thread."
// See clippy_exceptions.rb for full justification.
#[allow(unsafe_code)]
#[allow(clippy::non_send_fields_in_send_ty)]
unsafe impl Send for RbWebView {}

// SPDX-SnippetEnd

impl RbWebView {
    /// Create a new `WebView` attached to the given `Window`.
    ///
    /// The `ipc_callback` must be a `Ractor.shareable_proc`.
    ///
    /// # Errors
    ///
    /// Returns an error if `WebView` creation fails.
    // Magnus FFI requires owned types at the Ruby-Rust boundary.
    // See clippy_exceptions.rb for justification.
    #[allow(clippy::needless_pass_by_value)]
    pub fn new(
        window: &RbWindow,
        url: String,
        _ipc_callback: Value,
        proxy: &RbProxy,
    ) -> Result<Self, Error> {
        let proxy_clone = proxy.inner().clone();

        let webview = WebViewBuilder::new()
            .with_url(&url)
            .with_ipc_handler(move |msg| {
                let _ = proxy_clone.send_event(UserEvent::IpcMessage(msg.body().clone()));
            })
            .build(&window.inner)
            .map_err(|e| Error::new(runtime_error(), e.to_string()))?;

        Ok(Self { inner: webview })
    }

    // SPDX-SnippetBegin
    // SPDX-License-Identifier: Apache-2.0 OR MIT
    // SPDX-SnippetCopyrightText: 2020-2023 Tauri Programme within The Commons Conservancy
    // SPDX-SnippetComment: Async custom protocol pattern adapted from tauri/app.rs register_asynchronous_uri_scheme_protocol
    //                      Initial URL pattern adapted from tauri/manager/webview.rs WebviewUrl::App
    //                      Page load handler pattern adapted from tauri/webview/mod.rs on_page_load

    /// Create a new `WebView` with the `tokra://` custom protocol.
    ///
    /// This is the primary constructor for Rack-style apps. The `WebView` navigates
    /// to `tokra://localhost/` and Ruby handles all requests via `HttpRequestEvent`.
    /// Ruby controls everything: initial HTML, form submissions, API responses.
    ///
    /// This matches Tauri's pattern where apps load from `tauri://localhost/`.
    ///
    /// # Errors
    ///
    /// Returns an error if `WebView` creation fails.
    ///
    /// # Panics
    ///
    /// Panics if the responders mutex is poisoned (internal invariant violation).
    pub fn new_with_protocol(window: &RbWindow, proxy: &RbProxy) -> Result<Self, Error> {
        let proxy_clone = proxy.inner().clone();
        let proxy_for_protocol = proxy.inner().clone();
        let proxy_for_page_load = proxy.inner().clone();

        let webview = WebViewBuilder::new()
            .with_url("tokra://localhost/")
            .with_asynchronous_custom_protocol(
                "tokra".into(),
                move |_webview_id, request, responder| {
                    // Generate unique request ID
                    let request_id = next_request_id();

                    // Extract request details
                    let method = request.method().to_string();
                    let uri = request.uri().to_string();
                    let body = String::from_utf8_lossy(request.body()).to_string();

                    // Store the responder for later (Ruby will call back with the response)
                    get_responders()
                        .lock()
                        .unwrap()
                        .insert(request_id, responder);

                    // Send HTTP request through the event loop to Ruby
                    // Ruby will process and send back an HttpResponse event
                    let _ = proxy_for_protocol.send_event(UserEvent::HttpRequest {
                        request_id,
                        method,
                        uri,
                        body,
                    });
                },
            )
            .with_on_page_load_handler(move |event, url| {
                let event_name = match event {
                    PageLoadEvent::Started => "started",
                    PageLoadEvent::Finished => "finished",
                };
                let _ = proxy_for_page_load.send_event(UserEvent::PageLoad {
                    event: event_name.to_string(),
                    url,
                });
            })
            // SPDX-SnippetEnd
            .with_ipc_handler(move |msg| {
                let _ = proxy_clone.send_event(UserEvent::IpcMessage(msg.body().clone()));
            })
            .build(&window.inner)
            .map_err(|e| Error::new(runtime_error(), e.to_string()))?;

        Ok(Self { inner: webview })
    }

    /// Evaluate JavaScript in the `WebView`.
    ///
    /// # Errors
    ///
    /// Returns an error if JavaScript evaluation fails.
    // Magnus FFI requires owned types at the Ruby-Rust boundary.
    // See clippy_exceptions.rb for justification.
    #[allow(clippy::needless_pass_by_value)]
    pub fn eval(&self, js: String) -> Result<(), Error> {
        self.inner
            .evaluate_script(&js)
            .map_err(|e| Error::new(runtime_error(), e.to_string()))
    }
}

/// Define the `WebView` class methods on the given Ruby module.
///
/// # Errors
///
/// Returns an error if class or method definition fails.
pub fn define_class(ruby: &Ruby, native: magnus::RModule) -> Result<(), Error> {
    let webview_class = native.define_class("WebView", ruby.class_object())?;
    webview_class.define_singleton_method("new", function!(RbWebView::new, 4))?;
    webview_class.define_singleton_method(
        "new_with_protocol",
        function!(RbWebView::new_with_protocol, 2),
    )?;
    webview_class.define_method("eval", method!(RbWebView::eval, 1))?;
    Ok(())
}
