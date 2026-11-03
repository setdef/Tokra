// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! `WebView` wrapper for wry.
//!
//! This module provides the Ruby-facing `Tokra::Native::WebView` class,
//! which wraps `wry::WebView` and implements the tokra:// custom protocol.

use std::cell::{Cell, RefCell};

use magnus::{function, method, prelude::*, Error, Ruby};
use tao::event_loop::EventLoopProxy;
use wry::{PageLoadEvent, WebView, WebViewBuilder};

use crate::proxy::RbProxy;
use crate::responders::{get_responders, next_request_id};
use crate::runtime_error;
use crate::thread_bound::{wrong_thread, ThreadBound};
use crate::user_event::{Released, UserEvent};
use crate::window::RbWindow;

/// The Ruby class name, for the wrong-thread error.
const CLASS: &str = "Tokra::Native::WebView";

// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: Header extraction and request forwarding adapted from
//                      tauri/src/protocol/tauri.rs and tauri/src/ipc/protocol.rs

/// Forward one custom-protocol request to Ruby through the event loop.
///
/// Both the `tokra://` content protocol and the `ipc://` transport share this
/// path: store the wry responder by a fresh `request_id`, then send a
/// `UserEvent::HttpRequest` carrying the request and `label`, the id wry
/// hands the handler, which is the webview's label (`with_id`), as Tauri's
/// protocol context reads it (`manager/webview.rs:229-233`). Ruby routes on the URI scheme
/// and later replies (or drops) via the `Proxy` keyed by that `request_id`. wry
/// registers each scheme independently, so both protocols reuse one handler.
fn forward_request_to_ruby(
    proxy: &EventLoopProxy<UserEvent>,
    label: &str,
    request: &wry::http::Request<Vec<u8>>,
    responder: wry::RequestAsyncResponder,
) {
    let request_id = next_request_id();

    // Store the responder so Ruby can reply (or drop) it later by request_id.
    get_responders()
        .lock()
        .unwrap()
        .insert(request_id, responder);

    let _ = proxy.send_event(http_request_event(request_id, label, request));
}

/// Build the `UserEvent::HttpRequest` Ruby receives for one protocol request.
///
/// Headers carry cookies (ADR 002) and, on the ipc:// path, the Tauri-*
/// invoke headers and Origin that Ruby parses per ipc/protocol.rs. Values
/// keep their bytes, as Tauri hands `parts.headers` to the command
/// (ipc/protocol.rs:546); wry builds them from Rust Strings, so they are
/// UTF-8 and the lossy conversion never replaces anything. Ruby applies
/// `to_str`'s visible-ASCII rule where Tauri does. The body
/// travels as its exact bytes: a lossy UTF-8 conversion would corrupt binary
/// uploads.
fn http_request_event(
    request_id: u64,
    label: &str,
    request: &wry::http::Request<Vec<u8>>,
) -> UserEvent {
    let headers: Vec<(String, String)> = request
        .headers()
        .iter()
        .map(|(name, value)| {
            (
                name.to_string(),
                String::from_utf8_lossy(value.as_bytes()).into_owned(),
            )
        })
        .collect();

    UserEvent::HttpRequest {
        label: label.to_string(),
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
/// with the body, and with `label`, the webview's, which the handler
/// captured as tauri-runtime-wry's `create_ipc_handler` does
/// (`src/lib.rs:5169-5192`).
fn forward_ipc_message_to_ruby(
    proxy: &EventLoopProxy<UserEvent>,
    label: &str,
    msg: &wry::http::Request<String>,
) {
    let _ = proxy.send_event(UserEvent::IpcMessage {
        label: label.to_string(),
        url: msg.uri().to_string(),
        body: msg.body().clone(),
    });
}

// SPDX-SnippetEnd

// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: Webview placement adapted from tauri-runtime-wry/src/lib.rs create_webview

/// Build the webview as its window's content, the way Tauri does.
///
/// On Linux, Tauri builds into the window's GTK box (`build_gtk` on
/// `default_vbox`, tauri-runtime-wry `src/lib.rs:5032-5051`), and elsewhere
/// with `build`. wry's `build` on Linux takes its X11 path instead
/// (webkitgtk `mod.rs:140-190`): it works only on X11, and it adopts the
/// window's own X window, which it destroys when the webview drops
/// (`mod.rs:77-82`), so tao reports the window closing and the app ends.
#[cfg(not(any(target_os = "windows", target_os = "macos")))]
fn build_in(builder: WebViewBuilder<'_>, window: &tao::window::Window) -> wry::Result<WebView> {
    use tao::platform::unix::WindowExtUnix;
    use wry::WebViewBuilderExtUnix;

    let vbox = window
        .default_vbox()
        .ok_or(wry::Error::UnsupportedWindowHandle)?;
    builder.build_gtk(vbox)
}

/// Build the webview as its window's content, the way Tauri does (see the
/// Linux version).
#[cfg(any(target_os = "windows", target_os = "macos"))]
fn build_in(builder: WebViewBuilder<'_>, window: &tao::window::Window) -> wry::Result<WebView> {
    builder.build(window)
}

// SPDX-SnippetEnd

// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: The window content's resize handler adapted from tauri-runtime-wry/src/lib.rs create_webview

/// Lets a person resize an undecorated window by its edges, as Tauri does
/// once it has built the webview that is a window's content
/// (tauri-runtime-wry `src/lib.rs:5055-5067`): on Linux the webview gets
/// GTK handlers that begin the drag, and on Windows a resizable,
/// undecorated window gets the drag window over it
/// (`undecorated_resizing.rs`).
#[cfg(any(
    target_os = "linux",
    target_os = "dragonfly",
    target_os = "freebsd",
    target_os = "netbsd",
    target_os = "openbsd"
))]
fn attach_resize_handler(_window: &tao::window::Window, webview: &WebView) {
    crate::undecorated_resizing::attach_resize_handler(webview);
}

/// Lets a person resize an undecorated window by its edges (see the
/// Linux version).
#[cfg(windows)]
fn attach_resize_handler(window: &tao::window::Window, _webview: &WebView) {
    use tao::platform::windows::WindowExtWindows;

    if window.is_resizable() && !window.is_decorated() {
        crate::undecorated_resizing::attach_resize_handler(
            window.hwnd(),
            window.has_undecorated_shadow(),
        );
    }
}

/// macOS keeps an undecorated window resizable itself.
#[cfg(target_os = "macos")]
const fn attach_resize_handler(_window: &tao::window::Window, _webview: &WebView) {}

// SPDX-SnippetEnd

/// The webview rows a `Tokra::WebviewWindowBuilder` sets (plan 052,
/// decision c10), read from `open`'s Hash; a key it lacks keeps wry's
/// default, as `Default` does.
#[derive(Default)]
struct Attributes {
    focused: Option<bool>,
    transparent: Option<bool>,
    background_color: Option<(u8, u8, u8, u8)>,
    #[cfg(target_os = "macos")]
    traffic_light_position: Option<crate::window_state::Dimensions>,
}

impl Attributes {
    /// Reads `focused`, `transparent`, `background_color`, and on macOS
    /// `traffic_light_position` from `attributes`.
    ///
    /// # Errors
    ///
    /// Returns `TypeError` for a value of the wrong type.
    fn read(ruby: &Ruby, attributes: magnus::RHash) -> Result<Self, Error> {
        Ok(Self {
            focused: attributes.lookup(ruby.to_symbol("focused"))?,
            transparent: attributes.lookup(ruby.to_symbol("transparent"))?,
            background_color: attributes.lookup(ruby.to_symbol("background_color"))?,
            #[cfg(target_os = "macos")]
            traffic_light_position: attributes.lookup(ruby.to_symbol("traffic_light_position"))?,
        })
    }

    // SPDX-SnippetBegin
    // SPDX-License-Identifier: Apache-2.0 OR MIT
    // SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    // SPDX-SnippetComment: The webview attributes adapted from tauri-runtime-wry/src/lib.rs create_webview

    /// `builder` with these rows, as Tauri's `create_webview` sets them:
    /// focus and transparency always (`src/lib.rs:4626-4627`), the
    /// background color when given (`:4665-4667`), and on macOS the
    /// traffic-light inset (`:4943-4946`).
    fn apply<'a>(&self, mut builder: WebViewBuilder<'a>) -> WebViewBuilder<'a> {
        if let Some(focused) = self.focused {
            builder = builder.with_focused(focused);
        }
        if let Some(transparent) = self.transparent {
            builder = builder.with_transparent(transparent);
        }
        if let Some(color) = self.background_color {
            builder = builder.with_background_color(color);
        }
        #[cfg(target_os = "macos")]
        if let Some(position) = self.traffic_light_position {
            use wry::WebViewBuilderExtDarwin;
            builder = builder.with_traffic_light_inset(crate::window_state::position(position));
        }
        builder
    }

    // SPDX-SnippetEnd
}

// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2020-2023 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: Async custom protocol pattern adapted from tauri/app.rs register_asynchronous_uri_scheme_protocol
//                      Initial URL pattern adapted from tauri/manager/webview.rs WebviewUrl::App
//                      Page load handler pattern adapted from tauri/webview/mod.rs on_page_load

/// Build the webview labeled `label` into `window`, loading `url`, with the
/// `tokra://` and `ipc://` protocols and the IPC, page-load, drag-drop, and
/// (Windows) focus handlers, each naming `label` (see `new_with_protocol`),
/// and the webview rows in `attributes`.
///
/// # Errors
///
/// Returns `ThreadError` off the window's thread, or `RuntimeError` when
/// the window is closed or empty, when wry fails, or on Windows when
/// `WebView2` refuses a focus handler.
fn build(
    window: &RbWindow,
    proxy: &RbProxy,
    label: &str,
    url: String,
    initialization_scripts: Vec<String>,
    attributes: &Attributes,
) -> Result<WebView, Error> {
    let proxy_clone = proxy.inner().clone();
    let label_for_ipc_message = label.to_string();
    let proxy_for_protocol = proxy.inner().clone();
    let proxy_for_ipc = proxy.inner().clone();
    let proxy_for_page_load = proxy.inner().clone();
    let label_for_page_load = label.to_string();

    let mut builder = attributes.apply(WebViewBuilder::new().with_id(label));
    for script in initialization_scripts {
        builder = builder.with_initialization_script(script);
    }

    let builder = builder
        .with_url(url)
        // The tokra:// content protocol: Ruby serves HTML, assets, and Rack.
        .with_asynchronous_custom_protocol("tokra".into(), move |id, request, responder| {
            forward_request_to_ruby(&proxy_for_protocol, id, &request, responder);
        })
        // The ipc:// transport: Tauri's desktop-default invoke channel. Same
        // request shape, different scheme; Ruby dispatches on the URI scheme.
        .with_asynchronous_custom_protocol("ipc".into(), move |id, request, responder| {
            forward_request_to_ruby(&proxy_for_ipc, id, &request, responder);
        })
        .with_on_page_load_handler(move |event, url| {
            let event_name = match event {
                PageLoadEvent::Started => "started",
                PageLoadEvent::Finished => "finished",
            };
            let _ = proxy_for_page_load.send_event(UserEvent::PageLoad {
                label: label_for_page_load.clone(),
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
            let label_for_drag_drop = label.to_string();
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
                    label: label_for_drag_drop.clone(),
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
            forward_ipc_message_to_ruby(&proxy_clone, &label_for_ipc_message, &msg);
        });
    let tao_window = window.window()?;
    let builder = with_window_theme(builder, &tao_window);
    let webview =
        build_in(builder, &tao_window).map_err(|e| Error::new(runtime_error(), e.to_string()))?;
    attach_resize_handler(&tao_window, &webview);
    // Windows reports the window's focus from the webview's, as
    // tauri-runtime-wry's create_webview does (`src/lib.rs:5069-5130`).
    #[cfg(windows)]
    crate::webview_focus::attach(&webview, proxy.inner(), label)
        .map_err(|e| Error::new(runtime_error(), e.to_string()))?;
    drop(tao_window);
    Ok(webview)
}

// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: The webview's theme adapted from tauri-runtime-wry/src/lib.rs create_webview

/// On Windows the webview takes its window's theme, light for any theme
/// but dark, as Tauri's `create_webview` gives every webview
/// (tauri-runtime-wry `src/lib.rs:4877-4881`).
#[cfg(windows)]
fn with_window_theme<'a>(
    builder: WebViewBuilder<'a>,
    window: &tao::window::Window,
) -> WebViewBuilder<'a> {
    use wry::WebViewBuilderExtWindows;

    builder.with_theme(match window.theme() {
        tao::window::Theme::Dark => wry::Theme::Dark,
        _ => wry::Theme::Light,
    })
}

// SPDX-SnippetEnd

/// Elsewhere wry's webview has no theme of its own.
#[cfg(not(windows))]
const fn with_window_theme<'a>(
    builder: WebViewBuilder<'a>,
    _window: &tao::window::Window,
) -> WebViewBuilder<'a> {
    builder
}

/// Ruby wrapper for `wry::WebView`.
///
/// wry's `WebView` is not `Send`: the compiler infers that from the platform
/// webview it holds (wry `src/lib.rs:1944-1946`), a `WKWebView`, `WebKitGTK`,
/// or `WebView2` object tied to the thread that built it. magnus wraps only
/// `Send` types (magnus `src/typed_data.rs:411-413`). The webview lives in a
/// [`ThreadBound`], which is `Send` because it never reaches the webview
/// off the thread that built it, so this type needs no `unsafe impl` of its
/// own. Every method answers only that thread; `Tokra::Webview` brings each
/// call there (`Tokra::RuntimeContext`), as Tauri's runtime does for its
/// own main-thread types (tauri-runtime-wry `src/lib.rs:234-254`, `431-454`).
#[magnus::wrap(class = "Tokra::Native::WebView", free_immediately, size)]
pub struct RbWebView {
    /// Empty once `close` has dropped the webview.
    inner: RefCell<ThreadBound<WebView>>,
    /// Whether a wry webview was ever put in `inner`, so `open` never
    /// refills a webview that `close` emptied.
    opened: Cell<bool>,
    /// Carries the webview back to its thread if Ruby frees this object on
    /// another (see `Drop`).
    proxy: EventLoopProxy<UserEvent>,
}

impl Drop for RbWebView {
    /// Drop the webview on its own thread.
    ///
    /// Ruby frees this object on whichever thread sweeps it (Ruby v4.0.1
    /// `gc.c:1182-1222` runs a `free_immediately` type's free during the
    /// sweep, and lazy sweeping continues on any allocating thread,
    /// `gc/default/default.c:2062-2120`). Off the webview's thread this sends
    /// it to the loop, which drops it on the main thread
    /// (`UserEvent::Release`). If the loop is gone the event comes back and
    /// drops here, where the `ThreadBound` leaks the webview instead. No
    /// Ruby API is called, as `free_immediately` requires (magnus
    /// `src/typed_data.rs:310-316`).
    fn drop(&mut self) {
        let inner = self.inner.get_mut();
        if !inner.owner().is_current() {
            let _ = self
                .proxy
                .send_event(UserEvent::Release(Released::WebView(Box::new(
                    inner.take(),
                ))));
        }
    }
}

impl RbWebView {
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
    /// On Windows the window's focus events come from this webview's
    /// `GotFocus` and `LostFocus` (`webview_focus.rs`).
    ///
    /// The webview is built with `label` as wry's id, as Tauri's runtime
    /// builds each webview `with_id(&label)` (tauri-runtime-wry
    /// `src/lib.rs:4625`), and every event it sends carries `label`: its
    /// protocol requests read the id wry hands back, and its IPC, page-load,
    /// drag-drop, and (Windows) focus handlers capture a copy. A label
    /// belongs to one live webview: wry's macOS backend keeps each
    /// webview's protocol handlers in a process-wide table keyed by its id
    /// and removes the entry when a webview drops (`src/wkwebview/mod.rs:290-293`,
    /// `:1292-1294`), so two live webviews with one label share an entry,
    /// and dropping either leaves the other without its protocols. The
    /// caller keeps labels unique, as `Tokra::App` does.
    ///
    /// # Errors
    ///
    /// Returns `ArgumentError` for a label holding NUL, before building
    /// anything: wry copies the id into a C string with `unwrap` on macOS
    /// (`src/wkwebview/mod.rs:274-277`). Returns `ThreadError` off the
    /// window's thread, an error if `WebView` creation fails, or on Windows if
    /// `WebView2` refuses a focus handler. Tauri `unwrap()`s there
    /// (tauri-runtime-wry `src/lib.rs:5076-5130`); a panic across magnus
    /// would be a fatal error Ruby cannot rescue, so this raises
    /// `RuntimeError` instead.
    ///
    /// # Panics
    ///
    /// Panics if the responders mutex is poisoned (internal invariant violation).
    pub fn new_with_protocol(
        ruby: &Ruby,
        window: &RbWindow,
        proxy: &RbProxy,
        label: String,
        initialization_scripts: Vec<String>,
    ) -> Result<Self, Error> {
        let label = crate::window_labels::checked(ruby, label)?;
        let webview = build(
            window,
            proxy,
            &label,
            "tokra://localhost/".to_string(),
            initialization_scripts,
            &Attributes::default(),
        )?;
        Ok(Self {
            inner: RefCell::new(ThreadBound::new(webview)),
            opened: Cell::new(true),
            proxy: proxy.inner().clone(),
        })
    }

    /// An empty webview for the loop `proxy` wakes, owned by the loop's
    /// thread whichever thread calls this, for `open` to fill there.
    /// Until then it answers as a closed webview does, as `Window.empty`'s
    /// window does (plan 052, decision 4).
    #[must_use]
    pub fn empty(proxy: &RbProxy) -> Self {
        Self {
            inner: RefCell::new(ThreadBound::empty(proxy.loop_thread())),
            opened: Cell::new(false),
            proxy: proxy.inner().clone(),
        }
    }

    /// Build the webview `new_with_protocol` builds, labeled `label`, from
    /// `attributes`, as Tauri's `WebviewAttributes` holds them
    /// (tauri-runtime `src/webview.rs:323-398`): the `url` it loads, its
    /// `initialization_scripts`, and the webview rows (`focused`,
    /// `transparent`, `background_color`, and on macOS
    /// `traffic_light_position`), into this empty webview, as Tauri's
    /// runtime builds a webview window's webview right after its window
    /// (tauri-runtime-wry `src/lib.rs:4489-4500`).
    ///
    /// On Windows `WebView2` creation runs a nested message loop
    /// (webview2-com `wait_with_pump`) inside the event loop's callback, as
    /// it does in Tauri for every window it builds once its loop runs
    /// (plan 052, decision 5).
    ///
    /// # Errors
    ///
    /// Returns `ArgumentError` for a label holding NUL, `KeyError` without
    /// a `url` or `initialization_scripts`, and `TypeError` for an
    /// attribute of the wrong type, before building anything; `ThreadError`
    /// off the loop's thread; and `RuntimeError` when the webview is or
    /// ever was open, when `window` is closed or was never filled, or when
    /// wry fails to build it.
    pub fn open(
        ruby: &Ruby,
        rb_self: &Self,
        window: &RbWindow,
        proxy: &RbProxy,
        label: String,
        attributes: magnus::RHash,
    ) -> Result<(), Error> {
        let label = crate::window_labels::checked(ruby, label)?;
        let url: String = attributes.fetch(ruby.to_symbol("url"))?;
        let initialization_scripts: Vec<String> =
            attributes.fetch(ruby.to_symbol("initialization_scripts"))?;
        let attributes = Attributes::read(ruby, attributes)?;
        {
            let inner = rb_self
                .inner
                .try_borrow()
                .map_err(|_| Error::new(runtime_error(), "WebView is in use"))?;
            if !inner.owner().is_current() {
                return Err(wrong_thread(CLASS));
            }
            if rb_self.opened.get() {
                return Err(Error::new(runtime_error(), "WebView is already open"));
            }
        }
        let webview = build(
            window,
            proxy,
            &label,
            url,
            initialization_scripts,
            &attributes,
        )?;
        rb_self
            .inner
            .try_borrow_mut()
            .map_err(|_| Error::new(runtime_error(), "WebView is in use"))?
            .fill(webview)
            .map_err(|_| Error::new(runtime_error(), "WebView is already open"))?;
        rb_self.opened.set(true);
        Ok(())
    }

    /// Evaluate JavaScript in the `WebView`.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the webview's thread, or an error if
    /// JavaScript evaluation fails.
    // Magnus FFI requires owned types at the Ruby-Rust boundary.
    // See clippy_exceptions.rb for justification.
    #[allow(clippy::needless_pass_by_value)]
    pub fn eval(&self, js: String) -> Result<(), Error> {
        let inner = self
            .inner
            .try_borrow()
            .map_err(|_| Error::new(runtime_error(), "WebView is closing"))?;
        if !inner.owner().is_current() {
            return Err(wrong_thread(CLASS));
        }
        // A closed webview ignores the script, as Tauri's runtime ignores
        // a message for a webview it no longer holds.
        inner.get().map_or(Ok(()), |webview| {
            webview
                .evaluate_script(&js)
                .map_err(|e| Error::new(runtime_error(), e.to_string()))
        })
    }

    // SPDX-SnippetBegin
    // SPDX-License-Identifier: Apache-2.0 OR MIT
    // SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    // SPDX-SnippetComment: The webview's SetBackgroundColor arm adapted from tauri-runtime-wry/src/lib.rs handle_user_message
    /// wry's `WebView::set_background_color`, white for `nil`, as Tauri's
    /// runtime asks it (`src/lib.rs:3745-3750`). A closed webview ignores
    /// it.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the webview's thread, or a `RuntimeError`
    /// with wry's error, which `Tokra::Webview` logs as Tauri's runtime
    /// does.
    pub fn set_background_color(&self, color: Option<(u8, u8, u8, u8)>) -> Result<(), Error> {
        let inner = self
            .inner
            .try_borrow()
            .map_err(|_| Error::new(runtime_error(), "WebView is closing"))?;
        if !inner.owner().is_current() {
            return Err(wrong_thread(CLASS));
        }
        inner.get().map_or(Ok(()), |webview| {
            webview
                .set_background_color(color.unwrap_or((255, 255, 255, 255)))
                .map_err(|e| Error::new(runtime_error(), e.to_string()))
        })
    }
    // SPDX-SnippetEnd

    // SPDX-SnippetBegin
    // SPDX-License-Identifier: Apache-2.0 OR MIT
    // SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    // SPDX-SnippetComment: The webview's theme on ThemeChanged adapted from tauri-runtime-wry/src/lib.rs handle_event_loop
    /// wry's `WebViewExtWindows::set_theme`, which Tauri's runtime calls
    /// for each of a window's webviews when the system theme changes
    /// (`src/lib.rs:4153-4166`): `"Dark"` is dark and anything else
    /// light, as its match maps tao's theme. A closed webview ignores it.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the webview's thread, or a `RuntimeError`
    /// with wry's message when `WebView2` refuses the theme.
    #[cfg(windows)]
    pub fn set_theme(&self, name: magnus::RString) -> Result<(), Error> {
        use wry::WebViewExtWindows;

        let theme = if name.to_string()? == "Dark" {
            wry::Theme::Dark
        } else {
            wry::Theme::Light
        };
        let inner = self
            .inner
            .try_borrow()
            .map_err(|_| Error::new(runtime_error(), "WebView is closing"))?;
        if !inner.owner().is_current() {
            return Err(wrong_thread(CLASS));
        }
        inner.get().map_or(Ok(()), |webview| {
            webview
                .set_theme(theme)
                .map_err(|e| Error::new(runtime_error(), e.to_string()))
        })
    }
    // SPDX-SnippetEnd

    // SPDX-SnippetBegin
    // SPDX-License-Identifier: Apache-2.0 OR MIT
    // SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    // SPDX-SnippetComment: Dropping a closed window's webviews adapted from tauri-runtime-wry/src/lib.rs handle_event_loop
    /// Close the webview by dropping it, as Tauri's runtime drops a
    /// destroyed window's webviews with its store entry (tauri-runtime-wry
    /// `src/lib.rs:4171-4172`). Closing twice does nothing.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the webview's thread.
    pub fn close(&self) -> Result<(), Error> {
        let closed = {
            let mut inner = self
                .inner
                .try_borrow_mut()
                .map_err(|_| Error::new(runtime_error(), "WebView is in use"))?;
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

    /// The wry webview, on the thread that created it, or `None` once
    /// `close` has dropped it.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` on any other thread, or a `RuntimeError` while
    /// `close` holds the webview. Only macOS's `Window#inner_size` asks
    /// (`window_state.rs`).
    #[cfg(target_os = "macos")]
    pub(crate) fn open_webview(&self) -> Result<Option<std::cell::Ref<'_, WebView>>, Error> {
        let inner = self
            .inner
            .try_borrow()
            .map_err(|_| Error::new(runtime_error(), "WebView is closing"))?;
        if !inner.owner().is_current() {
            return Err(wrong_thread(CLASS));
        }
        Ok(std::cell::Ref::filter_map(inner, ThreadBound::get).ok())
    }
}

/// Define the `WebView` class methods on the given Ruby module.
///
/// # Errors
///
/// Returns an error if class or method definition fails.
pub fn define_class(ruby: &Ruby, native: magnus::RModule) -> Result<(), Error> {
    let webview_class = native.define_class("WebView", ruby.class_object())?;
    // `new_with_protocol` is the only constructor; without this, Class#new
    // would answer an empty object whose methods all raise.
    webview_class.undef_default_alloc_func();
    webview_class.define_singleton_method(
        "new_with_protocol",
        function!(RbWebView::new_with_protocol, 4),
    )?;
    webview_class.define_singleton_method("empty", function!(RbWebView::empty, 1))?;
    webview_class.define_method("open", method!(RbWebView::open, 4))?;
    webview_class.define_method("eval", method!(RbWebView::eval, 1))?;
    webview_class.define_method("close", method!(RbWebView::close, 0))?;
    webview_class.define_method(
        "set_background_color",
        method!(RbWebView::set_background_color, 1),
    )?;
    #[cfg(windows)]
    webview_class.define_method("set_theme", method!(RbWebView::set_theme, 1))?;
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

        match http_request_event(7, "side", &request) {
            UserEvent::HttpRequest {
                label,
                request_id,
                method,
                uri,
                headers,
                body: forwarded,
            } => {
                assert_eq!(label, "side", "the event names the webview wry passed");
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

    #[test]
    fn http_request_event_keeps_non_ascii_header_values() {
        let request = wry::http::Request::builder()
            .method("POST")
            .uri("ipc://localhost/upload")
            .header("x-probe", wry::http::HeaderValue::from_str("café").unwrap())
            .body(Vec::new())
            .unwrap();

        match http_request_event(1, "main", &request) {
            UserEvent::HttpRequest { headers, .. } => {
                assert_eq!(headers, vec![("x-probe".to_string(), "café".to_string())]);
            }
            other => panic!("expected HttpRequest, got {other:?}"),
        }
    }
}
