// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! Tokra Native Extension
//!
//! Thin Magnus bindings around `tao` (windowing) and `wry` (WebView).
//! Follows the "dumb pipe" principle: Rust handles platform-native operations
//! while Ruby manages all application logic, state, and routing.
//!
//! # Thread Safety Model
//!
//! This module follows the same thread safety patterns as Tauri. Window and
//! WebView types are not inherently Send-safe because they're bound to the
//! main OS thread. However, we mark our wrappers as Send with the following
//! invariant:
//!
//! **INVARIANT: All access to EventLoop, Window, and WebView happens
//! exclusively on the main thread via the tao event loop callback.**
//!
//! Ruby's Ractors communicate with the main thread through the Proxy, which
//! sends messages to wake the event loop. The event loop then processes these
//! on the main thread where Window/WebView access is safe.
//!
//! This pattern is identical to Tauri's `tauri-runtime-wry` crate:
//! - `unsafe impl Send for WindowsStore {}` (lib.rs:433)
//! - `unsafe impl Send for DispatcherMainThreadContext<T> {}` (lib.rs:451)
//! - `unsafe impl Send for WindowBuilderWrapper {}` (lib.rs:809)

use std::cell::RefCell;
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use magnus::{function, method, prelude::*, Error, Ruby, Value};
use tao::{
    event::{Event, WindowEvent},
    event_loop::{ControlFlow, EventLoop, EventLoopBuilder, EventLoopProxy},
    window::{Window, WindowBuilder},
};
use wry::{http, PageLoadEvent, RequestAsyncResponder, WebView, WebViewBuilder};

// =============================================================================
// UserEvent - Cross-thread communication payload
// =============================================================================

/// Custom event type for cross-thread/Ractor communication.
#[derive(Debug, Clone)]
pub enum UserEvent {
    /// IPC message received from WebView JavaScript
    IpcMessage(String),
    /// HTTP request received from WebView (via custom protocol)
    /// Contains: (request_id, method, uri, body)
    /// The request_id is used to correlate with the async response
    HttpRequest {
        request_id: u64,
        method: String,
        uri: String,
        body: String,
    },
    /// HTTP response from Ruby (for async protocol handling)
    /// Contains: (request_id, status, headers, body)
    HttpResponse {
        request_id: u64,
        status: u16,
        headers: Vec<(String, String)>,
        body: String,
    },
    /// Page load event (Started or Finished)
    /// Matches Tauri's on_page_load API
    PageLoad {
        event: String, // "started" or "finished"
        url: String,
    },
    /// Wake-up signal from a Ractor (via Proxy)
    WakeUp(String),
    /// Exit signal (from ctrlc handler)
    Exit,
}

// =============================================================================
// Helper Functions
// =============================================================================

/// Get the Ruby RuntimeError exception class.
///
/// This is a helper to avoid using the deprecated `magnus::exception::runtime_error()`.
fn runtime_error() -> magnus::ExceptionClass {
    Ruby::get()
        .expect("Ruby VM not initialized")
        .exception_runtime_error()
}

// =============================================================================
// Async Protocol Responder Storage
// =============================================================================

// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2020-2023 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: Async responder pattern adapted from tauri/app.rs register_asynchronous_uri_scheme_protocol

/// Global counter for generating unique request IDs
static NEXT_REQUEST_ID: AtomicU64 = AtomicU64::new(1);

/// Thread-safe storage for pending async responders
/// Maps request_id -> RequestAsyncResponder
static PENDING_RESPONDERS: std::sync::OnceLock<Mutex<HashMap<u64, RequestAsyncResponder>>> =
    std::sync::OnceLock::new();

fn get_responders() -> &'static Mutex<HashMap<u64, RequestAsyncResponder>> {
    PENDING_RESPONDERS.get_or_init(|| Mutex::new(HashMap::new()))
}

// SPDX-SnippetEnd

// =============================================================================
// RbEventLoop - Wraps tao::event_loop::EventLoop
// =============================================================================

/// Ruby wrapper for `tao::event_loop::EventLoop<UserEvent>`.
///
/// The EventLoop owns the OS main thread and runs the window event pump.
#[magnus::wrap(class = "Tokra::Native::EventLoop", free_immediately, size)]
struct RbEventLoop {
    /// The inner event loop. Wrapped in Option because `run` consumes it.
    inner: RefCell<Option<EventLoop<UserEvent>>>,
    /// Proxy for creating RbProxy instances before run() consumes the loop.
    proxy: RefCell<Option<EventLoopProxy<UserEvent>>>,
}

// SAFETY: RbEventLoop is only accessed from the main thread. The event loop
// itself runs on the main thread and all Ruby interactions happen there.
// This matches Tauri's pattern in tauri-runtime-wry.
// See clippy_exceptions.rb for full justification.
#[allow(unsafe_code)]
unsafe impl Send for RbEventLoop {}

impl RbEventLoop {
    /// Create a new EventLoop.
    fn new() -> Result<Self, Error> {
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
    fn create_proxy(&self) -> Result<RbProxy, Error> {
        let proxy = self.proxy.borrow().clone().ok_or_else(|| {
            Error::new(
                runtime_error(),
                "EventLoop has already been consumed by run()",
            )
        })?;

        Ok(RbProxy { inner: proxy })
    }

    /// Run the event loop (blocking, never returns under normal operation).
    ///
    /// The callback Proc is invoked for each event.
    fn run(&self, callback: Value) -> Result<(), Error> {
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
            let exit_sent_clone = exit_sent.clone();

            ctrlc::set_handler(move || {
                if !exit_sent_clone.swap(true, Ordering::SeqCst) {
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
                    UserEvent::IpcMessage(msg) => {
                        let event_obj = RbIpcEvent::new(msg);
                        let _ = callback.funcall::<_, _, Value>("call", (event_obj,));
                    }
                    UserEvent::HttpRequest {
                        request_id,
                        method,
                        uri,
                        body,
                    } => {
                        let event_obj = RbHttpRequestEvent::new(request_id, method, uri, body);
                        let _ = callback.funcall::<_, _, Value>("call", (event_obj,));
                    }
                    UserEvent::HttpResponse {
                        request_id,
                        status,
                        headers,
                        body,
                    } => {
                        if let Some(responder) =
                            get_responders().lock().unwrap().remove(&request_id)
                        {
                            let mut response_builder = http::Response::builder().status(status);
                            for (name, value) in headers {
                                response_builder = response_builder.header(name, value);
                            }
                            let response =
                                response_builder
                                    .body(body.into_bytes())
                                    .unwrap_or_else(|_| {
                                        http::Response::builder()
                                            .status(500)
                                            .body(b"Internal Error".to_vec())
                                            .unwrap()
                                    });
                            responder.respond(response);
                        }
                    }
                    UserEvent::PageLoad { event, url } => {
                        let event_obj = RbPageLoadEvent::new(event, url);
                        let _ = callback.funcall::<_, _, Value>("call", (event_obj,));
                    }
                    UserEvent::WakeUp(payload) => {
                        // Create a WakeUpEvent and call the Ruby callback
                        let event_obj = RbWakeUpEvent::new(payload);
                        let _ = callback.funcall::<_, _, Value>("call", (event_obj,));
                    }
                    UserEvent::Exit => {
                        *control_flow = ControlFlow::Exit;
                    }
                },
                Event::WindowEvent {
                    event: WindowEvent::CloseRequested,
                    ..
                } => {
                    // Create a WindowCloseEvent and call the Ruby callback
                    let event_obj = RbWindowCloseEvent::new();
                    let _ = callback.funcall::<_, _, Value>("call", (event_obj,));
                    *control_flow = ControlFlow::Exit;
                }
                _ => {}
            }
        });
    }
}

// =============================================================================
// RbWindow - Wraps tao::window::Window
// =============================================================================

/// Ruby wrapper for `tao::window::Window`.
#[magnus::wrap(class = "Tokra::Native::Window", free_immediately, size)]
struct RbWindow {
    inner: Window,
}

// SAFETY: RbWindow is only accessed from the main thread. Window operations
// are only performed within the event loop callback on the main thread.
// This matches Tauri's pattern in tauri-runtime-wry.
// See clippy_exceptions.rb for full justification.
#[allow(unsafe_code)]
unsafe impl Send for RbWindow {}

impl RbWindow {
    /// Create a new Window attached to the given EventLoop.
    fn new(event_loop: &RbEventLoop) -> Result<Self, Error> {
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
    fn set_title(&self, title: String) {
        self.inner.set_title(&title);
    }

    /// Set the window inner size.
    fn set_size(&self, width: f64, height: f64) {
        use tao::dpi::LogicalSize;
        let size = LogicalSize::new(width, height);
        self.inner.set_inner_size(size);
    }

    /// Get the window ID as a string.
    fn id(&self) -> String {
        format!("{:?}", self.inner.id())
    }
}

// =============================================================================
// RbWebView - Wraps wry::WebView
// =============================================================================

/// Ruby wrapper for `wry::WebView`.
#[magnus::wrap(class = "Tokra::Native::WebView", free_immediately, size)]
struct RbWebView {
    inner: WebView,
}

// SAFETY: RbWebView is only accessed from the main thread. WebView operations
// are only performed within the event loop callback on the main thread.
// This matches Tauri's pattern in tauri-runtime-wry where they use:
// `unsafe impl Send for WindowsStore {}` with the comment:
// "SAFETY: we ensure this type is only used on the main thread."
// See clippy_exceptions.rb for full justification.
#[allow(unsafe_code)]
unsafe impl Send for RbWebView {}

impl RbWebView {
    /// Create a new WebView attached to the given Window.
    ///
    /// The `ipc_callback` must be a `Ractor.shareable_proc`.
    fn new(
        window: &RbWindow,
        url: String,
        _ipc_callback: Value,
        proxy: &RbProxy,
    ) -> Result<Self, Error> {
        let proxy_clone = proxy.inner.clone();

        let webview = WebViewBuilder::new()
            .with_url(&url)
            .with_ipc_handler(move |msg| {
                let _ = proxy_clone.send_event(UserEvent::IpcMessage(msg.body().to_string()));
            })
            .build(&window.inner)
            .map_err(|e| Error::new(runtime_error(), e.to_string()))?;

        Ok(Self { inner: webview })
    }

    /// Create a new WebView with the `tokra://` custom protocol.
    ///
    /// This is the primary constructor for Rack-style apps. The WebView navigates
    /// to `tokra://localhost/` and Ruby handles all requests via HttpRequestEvent.
    /// Ruby controls everything: initial HTML, form submissions, API responses.
    ///
    /// This matches Tauri's pattern where apps load from `tauri://localhost/`.
    fn new_with_protocol(window: &RbWindow, proxy: &RbProxy) -> Result<Self, Error> {
        let proxy_clone = proxy.inner.clone();
        let proxy_for_protocol = proxy.inner.clone();
        let proxy_for_page_load = proxy.inner.clone();

        // SPDX-SnippetBegin
        // SPDX-License-Identifier: Apache-2.0 OR MIT
        // SPDX-SnippetCopyrightText: 2020-2023 Tauri Programme within The Commons Conservancy
        // SPDX-SnippetComment: Async custom protocol pattern adapted from tauri/app.rs register_asynchronous_uri_scheme_protocol
        //                      Initial URL pattern adapted from tauri/manager/webview.rs WebviewUrl::App
        //                      Page load handler pattern adapted from tauri/webview/mod.rs on_page_load
        let webview = WebViewBuilder::new()
            .with_url("tokra://localhost/")
            .with_asynchronous_custom_protocol(
                "tokra".into(),
                move |_webview_id, request, responder| {
                    // Generate unique request ID
                    let request_id = NEXT_REQUEST_ID.fetch_add(1, Ordering::SeqCst);

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
                let _ = proxy_clone.send_event(UserEvent::IpcMessage(msg.body().to_string()));
            })
            .build(&window.inner)
            .map_err(|e| Error::new(runtime_error(), e.to_string()))?;

        Ok(Self { inner: webview })
    }

    /// Evaluate JavaScript in the WebView.
    fn eval(&self, js: String) -> Result<(), Error> {
        self.inner
            .evaluate_script(&js)
            .map_err(|e| Error::new(runtime_error(), e.to_string()))
    }
}

// =============================================================================
// RbProxy - Wraps tao::event_loop::EventLoopProxy
// =============================================================================

/// Ruby wrapper for `tao::event_loop::EventLoopProxy<UserEvent>`.
///
/// Thread-safe handle for waking up the event loop from Ractors.
/// This is the ONLY type that is genuinely designed to be Send+Sync safe by tao.
///
/// This type uses `frozen_shareable` to be Ractor-shareable when frozen.
/// Ruby automatically freezes objects shared across Ractors.
#[derive(Clone)]
struct RbProxy {
    inner: EventLoopProxy<UserEvent>,
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
        static CLASS: magnus::value::Lazy<magnus::RClass> = magnus::value::Lazy::new(|ruby| {
            let tokra = ruby.define_module("Tokra").unwrap();
            let native = tokra.define_module("Native").unwrap();
            let class = native.define_class("Proxy", ruby.class_object()).unwrap();
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

impl RbProxy {
    /// Wake up the event loop with a payload.
    ///
    /// This is the critical method for Worker Ractor → Main Ractor communication.
    fn wake_up(&self, payload: String) -> Result<(), Error> {
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
    /// This is used by Ruby to respond to tokra:// requests.
    /// The request_id must match a pending HttpRequest event.
    /// Headers should be an array of [name, value] pairs.
    fn respond(
        &self,
        request_id: u64,
        status: u16,
        headers: Vec<(String, String)>,
        body: String,
    ) -> Result<(), Error> {
        self.inner
            .send_event(UserEvent::HttpResponse {
                request_id,
                status,
                headers,
                body,
            })
            .map_err(|_| {
                Error::new(
                    runtime_error(),
                    "Failed to send HTTP response: event loop closed",
                )
            })
    }
}

// =============================================================================
// Event Classes - Ruby event types for the callback
// =============================================================================

/// Simple Ruby class for IPC events.
#[magnus::wrap(class = "Tokra::Native::IpcEvent", free_immediately, size)]
struct RbIpcEvent {
    message: String,
}

impl RbIpcEvent {
    fn new(message: String) -> Self {
        Self { message }
    }

    fn message(&self) -> String {
        self.message.clone()
    }
}

/// Simple Ruby class for wake-up events.
#[magnus::wrap(class = "Tokra::Native::WakeUpEvent", free_immediately, size)]
struct RbWakeUpEvent {
    payload: String,
}

impl RbWakeUpEvent {
    fn new(payload: String) -> Self {
        Self { payload }
    }

    fn payload(&self) -> String {
        self.payload.clone()
    }
}

/// Simple Ruby class for window close events.
#[magnus::wrap(class = "Tokra::Native::WindowCloseEvent", free_immediately, size)]
struct RbWindowCloseEvent;

impl RbWindowCloseEvent {
    fn new() -> Self {
        Self
    }
}

/// Ruby class for HTTP request events (from tokra:// custom protocol).
/// Includes request_id for correlating async responses.
#[magnus::wrap(class = "Tokra::Native::HttpRequestEvent", free_immediately, size)]
struct RbHttpRequestEvent {
    request_id: u64,
    method: String,
    uri: String,
    body: String,
}

impl RbHttpRequestEvent {
    fn new(request_id: u64, method: String, uri: String, body: String) -> Self {
        Self {
            request_id,
            method,
            uri,
            body,
        }
    }

    fn request_id(&self) -> u64 {
        self.request_id
    }

    fn method(&self) -> String {
        self.method.clone()
    }

    fn uri(&self) -> String {
        self.uri.clone()
    }

    fn body(&self) -> String {
        self.body.clone()
    }
}

// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2020-2023 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: PageLoadEvent pattern adapted from tauri/webview/mod.rs on_page_load

/// Ruby class for page load events (started/finished).
/// Matches Tauri's on_page_load API.
#[magnus::wrap(class = "Tokra::Native::PageLoadEvent", free_immediately, size)]
struct RbPageLoadEvent {
    event: String, // "started" or "finished"
    url: String,
}

impl RbPageLoadEvent {
    fn new(event: String, url: String) -> Self {
        Self { event, url }
    }

    /// Returns "started" or "finished"
    fn event(&self) -> String {
        self.event.clone()
    }

    fn url(&self) -> String {
        self.url.clone()
    }

    /// Returns true if this is a "started" event
    fn started(&self) -> bool {
        self.event == "started"
    }

    /// Returns true if this is a "finished" event
    fn finished(&self) -> bool {
        self.event == "finished"
    }
}

// SPDX-SnippetEnd

// =============================================================================
// Module Initialization
// =============================================================================

/// Initialize the Tokra Ruby module.
///
/// # Errors
///
/// Returns an error if module or method definition fails.
#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let tokra = ruby.define_module("Tokra")?;
    let native = tokra.define_module("Native")?;

    // EventLoop
    let event_loop_class = native.define_class("EventLoop", ruby.class_object())?;
    event_loop_class.define_singleton_method("new", function!(RbEventLoop::new, 0))?;
    event_loop_class.define_method("create_proxy", method!(RbEventLoop::create_proxy, 0))?;
    event_loop_class.define_method("run", method!(RbEventLoop::run, 1))?;

    // Window
    let window_class = native.define_class("Window", ruby.class_object())?;
    window_class.define_singleton_method("new", function!(RbWindow::new, 1))?;
    window_class.define_method("set_title", method!(RbWindow::set_title, 1))?;
    window_class.define_method("set_size", method!(RbWindow::set_size, 2))?;
    window_class.define_method("id", method!(RbWindow::id, 0))?;

    // WebView
    let webview_class = native.define_class("WebView", ruby.class_object())?;
    webview_class.define_singleton_method("new", function!(RbWebView::new, 4))?;
    webview_class.define_singleton_method(
        "new_with_protocol",
        function!(RbWebView::new_with_protocol, 2),
    )?;
    webview_class.define_method("eval", method!(RbWebView::eval, 1))?;

    // Proxy
    let proxy_class = native.define_class("Proxy", ruby.class_object())?;
    proxy_class.define_method("wake_up", method!(RbProxy::wake_up, 1))?;
    proxy_class.define_method("respond", method!(RbProxy::respond, 4))?;

    // Event classes
    let ipc_event_class = native.define_class("IpcEvent", ruby.class_object())?;
    ipc_event_class.define_singleton_method("new", function!(RbIpcEvent::new, 1))?;
    ipc_event_class.define_method("message", method!(RbIpcEvent::message, 0))?;

    let wake_up_event_class = native.define_class("WakeUpEvent", ruby.class_object())?;
    wake_up_event_class.define_singleton_method("new", function!(RbWakeUpEvent::new, 1))?;
    wake_up_event_class.define_method("payload", method!(RbWakeUpEvent::payload, 0))?;

    let window_close_event_class = native.define_class("WindowCloseEvent", ruby.class_object())?;
    window_close_event_class
        .define_singleton_method("new", function!(RbWindowCloseEvent::new, 0))?;

    let http_request_event_class = native.define_class("HttpRequestEvent", ruby.class_object())?;
    http_request_event_class
        .define_singleton_method("new", function!(RbHttpRequestEvent::new, 4))?;
    http_request_event_class
        .define_method("request_id", method!(RbHttpRequestEvent::request_id, 0))?;
    http_request_event_class.define_method("method", method!(RbHttpRequestEvent::method, 0))?;
    http_request_event_class.define_method("uri", method!(RbHttpRequestEvent::uri, 0))?;
    http_request_event_class.define_method("body", method!(RbHttpRequestEvent::body, 0))?;

    let page_load_event_class = native.define_class("PageLoadEvent", ruby.class_object())?;
    page_load_event_class.define_singleton_method("new", function!(RbPageLoadEvent::new, 2))?;
    page_load_event_class.define_method("event", method!(RbPageLoadEvent::event, 0))?;
    page_load_event_class.define_method("url", method!(RbPageLoadEvent::url, 0))?;
    page_load_event_class.define_method("started?", method!(RbPageLoadEvent::started, 0))?;
    page_load_event_class.define_method("finished?", method!(RbPageLoadEvent::finished, 0))?;

    Ok(())
}
