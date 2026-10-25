// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! `WebView` wrapper for wry.
//!
//! This module provides the Ruby-facing `Tokra::Native::WebView` class,
//! which wraps `wry::WebView` and implements the tokra:// custom protocol.

use magnus::{function, method, prelude::*, Error, Ruby, Value};
use tao::event_loop::EventLoopProxy;
use wry::{PageLoadEvent, WebView, WebViewBuilder};

use crate::proxy::RbProxy;
use crate::responders::{get_responders, next_request_id};
use crate::runtime_error;
use crate::user_event::UserEvent;
use crate::window::RbWindow;

// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: Header extraction and request forwarding adapted from
//                      tauri/src/protocol/tauri.rs and tauri/src/ipc/protocol.rs

/// Forward one custom-protocol request to Ruby through the event loop.
///
/// Both the `tokra://` content protocol and the `ipc://` transport share this
/// path: store the wry responder by a fresh `request_id`, then send a
/// `UserEvent::HttpRequest` carrying the request. Ruby routes on the URI scheme
/// and later replies (or drops) via the `Proxy` keyed by that `request_id`. wry
/// registers each scheme independently, so both protocols reuse one handler.
fn forward_request_to_ruby(
    proxy: &EventLoopProxy<UserEvent>,
    request: &wry::http::Request<Vec<u8>>,
    responder: wry::RequestAsyncResponder,
) {
    let request_id = next_request_id();

    // Store the responder so Ruby can reply (or drop) it later by request_id.
    get_responders()
        .lock()
        .unwrap()
        .insert(request_id, responder);

    let _ = proxy.send_event(http_request_event(request_id, request));
}

/// Build the `UserEvent::HttpRequest` Ruby receives for one protocol request.
///
/// Headers carry cookies (ADR 002) and, on the ipc:// path, the Tauri-*
/// invoke headers and Origin that Ruby parses per ipc/protocol.rs. The body
/// travels as its exact bytes: a lossy UTF-8 conversion would corrupt binary
/// uploads.
fn http_request_event(request_id: u64, request: &wry::http::Request<Vec<u8>>) -> UserEvent {
    let headers: Vec<(String, String)> = request
        .headers()
        .iter()
        .map(|(name, value)| (name.to_string(), value.to_str().unwrap_or("").to_string()))
        .collect();

    UserEvent::HttpRequest {
        request_id,
        method: request.method().to_string(),
        uri: request.uri().to_string(),
        headers,
        body: request.body().clone(),
    }
}

/// Forward one `window.ipc.postMessage` call to Ruby through the event loop.
///
/// wry sets the request URI to the sending frame's URL; Tauri parses it as
/// the invoke origin (`ipc/protocol.rs` `handle_ipc_message`), so it travels
/// with the body.
fn forward_ipc_message_to_ruby(
    proxy: &EventLoopProxy<UserEvent>,
    msg: &wry::http::Request<String>,
) {
    let _ = proxy.send_event(UserEvent::IpcMessage {
        url: msg.uri().to_string(),
        body: msg.body().clone(),
    });
}

// SPDX-SnippetEnd

/// Ruby wrapper for `wry::WebView`.
#[magnus::wrap(class = "Tokra::Native::WebView", free_immediately, size)]
pub struct RbWebView {
    inner: WebView,
}

// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2020-2023 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: Thread safety pattern adapted from tauri-runtime-wry/lib.rs unsafe impl Send for WindowsStore

// SAFETY: wry's `WebView` is not `Send`: the compiler infers that from the
// platform webview it holds (wry src/lib.rs:1944-1946), a WKWebView,
// WebKitGTK, or WebView2 object tied to the thread that built it. magnus wraps
// only `Send` types (magnus src/typed_data.rs:411-413) since any Ruby
// thread can reach a Ruby object. This impl is sound only while every call
// and the drop happen on the main thread, the invariant Tauri states for
// its own `unsafe impl Send for WindowsStore {}`: "we ensure this type is
// only used on the main thread" (tauri-runtime-wry src/lib.rs:431-433).
// Tokra's Ruby layer builds webviews only in App#run, beside the event
// loop tao confines to the main thread, and makes its own calls from the
// loop's callbacks. This extension never calls rb_ext_ractor_safe, so Ruby
// refuses its methods to every other Ractor (doc/extension.rdoc:2215-2217
// at Ruby v4.0.1). Nothing here stops app code on another Ruby Thread in
// the main Ractor from calling a webview (Tokra::Webview#eval reaches it
// directly), or a garbage collection on such a thread from freeing it:
// Plan 019 records that gap.
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
                forward_ipc_message_to_ruby(&proxy_clone, &msg);
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
    /// `initialization_scripts` run in the page before any of its own
    /// code, in order — Ruby assembles them (Tauri's `__TAURI_INTERNALS__`
    /// bootstrap and IPC scripts); this layer just passes strings through.
    ///
    /// # Errors
    ///
    /// Returns an error if `WebView` creation fails.
    ///
    /// # Panics
    ///
    /// Panics if the responders mutex is poisoned (internal invariant violation).
    pub fn new_with_protocol(
        window: &RbWindow,
        proxy: &RbProxy,
        initialization_scripts: Vec<String>,
    ) -> Result<Self, Error> {
        let proxy_clone = proxy.inner().clone();
        let proxy_for_protocol = proxy.inner().clone();
        let proxy_for_ipc = proxy.inner().clone();
        let proxy_for_page_load = proxy.inner().clone();

        let mut builder = WebViewBuilder::new();
        for script in initialization_scripts {
            builder = builder.with_initialization_script(script);
        }

        let webview = builder
            .with_url("tokra://localhost/")
            // The tokra:// content protocol: Ruby serves HTML, assets, and Rack.
            .with_asynchronous_custom_protocol("tokra".into(), move |_id, request, responder| {
                forward_request_to_ruby(&proxy_for_protocol, &request, responder);
            })
            // The ipc:// transport: Tauri's desktop-default invoke channel. Same
            // request shape, different scheme; Ruby dispatches on the URI scheme.
            .with_asynchronous_custom_protocol("ipc".into(), move |_id, request, responder| {
                forward_request_to_ruby(&proxy_for_ipc, &request, responder);
            })
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
            // SPDX-SnippetBegin
            // SPDX-License-Identifier: Apache-2.0 OR MIT
            // SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
            // SPDX-SnippetComment: Drag-drop handler pattern adapted from tauri-runtime-wry/lib.rs lines 4669-4703
            .with_drag_drop_handler({
                let proxy_for_drag_drop = proxy.inner().clone();
                move |event| {
                    use wry::DragDropEvent as WryDragDropEvent;

                    let (event_name, paths, x, y) = match event {
                        WryDragDropEvent::Enter {
                            paths,
                            position: (x, y),
                        } => (
                            "enter",
                            paths
                                .iter()
                                .map(|p| p.to_string_lossy().to_string())
                                .collect(),
                            x,
                            y,
                        ),
                        WryDragDropEvent::Over { position: (x, y) } => ("over", vec![], x, y),
                        WryDragDropEvent::Drop {
                            paths,
                            position: (x, y),
                        } => (
                            "drop",
                            paths
                                .iter()
                                .map(|p| p.to_string_lossy().to_string())
                                .collect(),
                            x,
                            y,
                        ),
                        WryDragDropEvent::Leave => ("leave", vec![], 0, 0),
                        _ => return true, // Handle future variants gracefully
                    };

                    let _ = proxy_for_drag_drop.send_event(UserEvent::DragDrop {
                        event: event_name.to_string(),
                        paths,
                        x,
                        y,
                    });
                    true // Block default OS behavior (like Tauri)
                }
            })
            // SPDX-SnippetEnd
            .with_ipc_handler(move |msg| {
                forward_ipc_message_to_ruby(&proxy_clone, &msg);
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
        function!(RbWebView::new_with_protocol, 3),
    )?;
    webview_class.define_method("eval", method!(RbWebView::eval, 1))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{http_request_event, UserEvent};

    #[test]
    fn http_request_event_passes_the_body_through_as_exact_bytes() {
        // A PNG signature: not valid UTF-8, so a lossy conversion would
        // replace bytes with U+FFFD.
        let body = vec![0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A, 0xFF, 0x00];
        let request = wry::http::Request::builder()
            .method("POST")
            .uri("ipc://localhost/upload")
            .header("Tauri-Callback", "12")
            .body(body.clone())
            .unwrap();

        match http_request_event(7, &request) {
            UserEvent::HttpRequest {
                request_id,
                method,
                uri,
                headers,
                body: forwarded,
            } => {
                assert_eq!(request_id, 7);
                assert_eq!(method, "POST");
                assert_eq!(uri, "ipc://localhost/upload");
                assert_eq!(
                    headers,
                    vec![("tauri-callback".to_string(), "12".to_string())],
                    "the http crate lowercases header names"
                );
                assert_eq!(forwarded, body, "the body must arrive byte for byte");
            }
            other => panic!("expected HttpRequest, got {other:?}"),
        }
    }
}
