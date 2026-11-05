// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! `WebView` wrapper for wry.
//!
//! This module provides the Ruby-facing `Tokra::Native::WebView` class,
//! which wraps `wry::WebView` and implements the tokra:// custom protocol.

use std::cell::{Cell, RefCell};
use std::path::PathBuf;

use magnus::{function, method, prelude::*, Error, Ruby};
use tao::event_loop::EventLoopProxy;
use wry::{PageLoadEvent, WebView, WebViewBuilder};

use crate::proxy::RbProxy;
use crate::responders::{get_responders, next_request_id};
use crate::runtime_error;
use crate::thread_bound::{wrong_thread, ThreadBound};
use crate::user_event::{Released, UserEvent};
use crate::web_context::{Lease, Lent};
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

/// The webview rows a `Tokra::WebviewBuilder` sets (plan 052, decisions
/// c10 and e1-2), read from `open`'s Hash; a key it lacks keeps wry's
/// default, as `Default` does. Each platform reads only its own keys,
/// though Ruby sends every key everywhere.
#[derive(Default)]
struct Attributes {
    focused: Option<bool>,
    transparent: Option<bool>,
    background_color: Option<(u8, u8, u8, u8)>,
    accept_first_mouse: Option<bool>,
    incognito: Option<bool>,
    clipboard: Option<bool>,
    /// `None` keeps the handler, as Tauri's default does.
    drag_drop_handler_enabled: Option<bool>,
    user_agent: Option<String>,
    proxy_config: Option<wry::ProxyConfig>,
    background_throttling: Option<wry::BackgroundThrottlingPolicy>,
    javascript_disabled: Option<bool>,
    /// The web context's key: its data directory, `None` for the default.
    data_directory: Option<PathBuf>,
    #[cfg(windows)]
    use_https_scheme: Option<bool>,
    #[cfg(windows)]
    additional_browser_args: Option<String>,
    #[cfg(windows)]
    browser_extensions_enabled: Option<bool>,
    #[cfg(windows)]
    scroll_bar_style: Option<wry::ScrollBarStyle>,
    #[cfg(any(
        windows,
        target_os = "linux",
        target_os = "dragonfly",
        target_os = "freebsd",
        target_os = "netbsd",
        target_os = "openbsd"
    ))]
    extensions_path: Option<String>,
    #[cfg(target_os = "macos")]
    data_store_identifier: Option<[u8; 16]>,
    #[cfg(target_os = "macos")]
    allow_link_preview: Option<bool>,
    #[cfg(target_os = "macos")]
    traffic_light_position: Option<crate::window_state::Dimensions>,
}

impl Attributes {
    /// Reads the webview rows from `attributes`, each platform its own,
    /// before anything is built.
    ///
    /// # Errors
    ///
    /// Returns `TypeError` for a value of the wrong type, `ArgumentError`
    /// for a policy or style no variant names, and `RuntimeError` "Invalid
    /// proxy url" for a proxy whose scheme `parse_proxy_url` refuses.
    fn read(ruby: &Ruby, attributes: magnus::RHash) -> Result<Self, Error> {
        let key = |name: &str| ruby.to_symbol(name);
        let proxy_url: Option<(String, String, String)> = attributes.lookup(key("proxy_url"))?;
        let policy: Option<String> = attributes.lookup(key("background_throttling"))?;
        let data_directory: Option<String> = attributes.lookup(key("data_directory"))?;
        #[cfg(windows)]
        let style: Option<String> = attributes.lookup(key("scroll_bar_style"))?;
        Ok(Self {
            focused: attributes.lookup(key("focused"))?,
            transparent: attributes.lookup(key("transparent"))?,
            background_color: attributes.lookup(key("background_color"))?,
            accept_first_mouse: attributes.lookup(key("accept_first_mouse"))?,
            incognito: attributes.lookup(key("incognito"))?,
            clipboard: attributes.lookup(key("clipboard"))?,
            drag_drop_handler_enabled: attributes.lookup(key("drag_drop_handler_enabled"))?,
            user_agent: attributes.lookup(key("user_agent"))?,
            proxy_config: proxy_url
                .map(|(scheme, host, port)| proxy_config(&scheme, host, port))
                .transpose()
                .map_err(|message| Error::new(ruby.exception_runtime_error(), message))?,
            background_throttling: policy
                .map(|name| background_throttling(&name))
                .transpose()
                .map_err(|message| Error::new(ruby.exception_arg_error(), message))?,
            javascript_disabled: attributes.lookup(key("javascript_disabled"))?,
            data_directory: data_directory.map(PathBuf::from),
            #[cfg(windows)]
            use_https_scheme: attributes.lookup(key("use_https_scheme"))?,
            #[cfg(windows)]
            additional_browser_args: attributes.lookup(key("additional_browser_args"))?,
            #[cfg(windows)]
            browser_extensions_enabled: attributes.lookup(key("browser_extensions_enabled"))?,
            #[cfg(windows)]
            scroll_bar_style: style
                .map(|name| scroll_bar_style(&name))
                .transpose()
                .map_err(|message| Error::new(ruby.exception_arg_error(), message))?,
            #[cfg(any(
                windows,
                target_os = "linux",
                target_os = "dragonfly",
                target_os = "freebsd",
                target_os = "netbsd",
                target_os = "openbsd"
            ))]
            extensions_path: attributes.lookup(key("extensions_path"))?,
            #[cfg(target_os = "macos")]
            data_store_identifier: attributes.lookup(key("data_store_identifier"))?,
            #[cfg(target_os = "macos")]
            allow_link_preview: attributes.lookup(key("allow_link_preview"))?,
            #[cfg(target_os = "macos")]
            traffic_light_position: attributes.lookup(key("traffic_light_position"))?,
        })
    }

    /// The drag-drop handler `make` builds, or `None` when a row turned it
    /// off. The default, a key absent or `true`, installs it, as Tauri's
    /// `WebviewAttributes::new` sets `drag_drop_handler_enabled: true` and
    /// its runtime installs the handler only then (tauri-runtime
    /// `src/webview.rs:488`; tauri-runtime-wry `src/lib.rs:4669`).
    fn drag_drop_handler<H>(&self, make: impl FnOnce() -> H) -> Option<H> {
        self.drag_drop_handler_enabled.unwrap_or(true).then(make)
    }

    // SPDX-SnippetBegin
    // SPDX-License-Identifier: Apache-2.0 OR MIT
    // SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    // SPDX-SnippetComment: The webview attributes adapted from tauri-runtime-wry/src/lib.rs create_webview

    /// `builder` with these rows, as Tauri's `create_webview` sets them
    /// (`src/lib.rs:4626-4946`): focus, transparency, first mouse,
    /// incognito, and the clipboard always; the background throttling,
    /// JavaScript, background color, user agent, and proxy when given;
    /// then each platform's own (`apply_platform`).
    fn apply<'a>(&self, mut builder: WebViewBuilder<'a>) -> WebViewBuilder<'a> {
        if let Some(focused) = self.focused {
            builder = builder.with_focused(focused);
        }
        if let Some(transparent) = self.transparent {
            builder = builder.with_transparent(transparent);
        }
        if let Some(accept) = self.accept_first_mouse {
            builder = builder.with_accept_first_mouse(accept);
        }
        if let Some(incognito) = self.incognito {
            builder = builder.with_incognito(incognito);
        }
        if let Some(clipboard) = self.clipboard {
            builder = builder.with_clipboard(clipboard);
        }
        if let Some(policy) = &self.background_throttling {
            builder = builder.with_background_throttling(policy.clone());
        }
        if self.javascript_disabled == Some(true) {
            builder = builder.with_javascript_disabled();
        }
        if let Some(color) = self.background_color {
            builder = builder.with_background_color(color);
        }
        if let Some(user_agent) = &self.user_agent {
            builder = builder.with_user_agent(user_agent);
        }
        if let Some(config) = &self.proxy_config {
            builder = builder.with_proxy_config(config.clone());
        }
        self.apply_platform(builder)
    }

    /// The Windows rows: the https scheme (`src/lib.rs:4642-4645`), the
    /// rows at `:4866-4895`, and the extensions path (`:4897-4909`).
    #[cfg(windows)]
    fn apply_platform<'a>(&self, mut builder: WebViewBuilder<'a>) -> WebViewBuilder<'a> {
        use wry::WebViewBuilderExtWindows;

        if let Some(enabled) = self.use_https_scheme {
            builder = builder.with_https_scheme(enabled);
        }
        if let Some(args) = &self.additional_browser_args {
            builder = builder.with_additional_browser_args(args);
        }
        if let Some(style) = self.scroll_bar_style {
            builder = builder.with_scroll_bar_style(style);
        }
        if let Some(enabled) = self.browser_extensions_enabled {
            builder = builder.with_browser_extensions_enabled(enabled);
        }
        if let Some(path) = &self.extensions_path {
            builder = builder.with_extensions_path(path);
        }
        builder
    }

    /// The Linux extensions path (`src/lib.rs:4897-4909`).
    #[cfg(any(
        target_os = "linux",
        target_os = "dragonfly",
        target_os = "freebsd",
        target_os = "netbsd",
        target_os = "openbsd"
    ))]
    fn apply_platform<'a>(&self, mut builder: WebViewBuilder<'a>) -> WebViewBuilder<'a> {
        use wry::WebViewBuilderExtUnix;

        if let Some(path) = &self.extensions_path {
            builder = builder.with_extensions_path(path);
        }
        builder
    }

    /// The macOS rows: the data store and the link preview
    /// (`src/lib.rs:4923-4932`), and the traffic-light inset (`:4941-4946`).
    #[cfg(target_os = "macos")]
    fn apply_platform<'a>(&self, mut builder: WebViewBuilder<'a>) -> WebViewBuilder<'a> {
        use wry::WebViewBuilderExtDarwin;

        if let Some(identifier) = self.data_store_identifier {
            builder = builder.with_data_store_identifier(identifier);
        }
        if let Some(allow) = self.allow_link_preview {
            builder = builder.with_allow_link_preview(allow);
        }
        if let Some(position) = self.traffic_light_position {
            builder = builder.with_traffic_light_inset(crate::window_state::position(position));
        }
        builder
    }
}

/// wry's policy for the name a `Tokra::BackgroundThrottlingPolicy` gives,
/// as Tauri's `create_webview` maps its own (`src/lib.rs:4647-4659`), or
/// the message for a name no policy has.
fn background_throttling(name: &str) -> Result<wry::BackgroundThrottlingPolicy, String> {
    match name {
        "Disabled" => Ok(wry::BackgroundThrottlingPolicy::Disabled),
        "Suspend" => Ok(wry::BackgroundThrottlingPolicy::Suspend),
        "Throttle" => Ok(wry::BackgroundThrottlingPolicy::Throttle),
        other => Err(format!("unknown background throttling policy: {other}")),
    }
}

/// wry's scroll bar style for the name a `Tokra::ScrollBarStyle` gives, as
/// Tauri's `create_webview` maps its own (`src/lib.rs:4883-4889`), or the
/// message for a name no style has.
#[cfg(windows)]
fn scroll_bar_style(name: &str) -> Result<wry::ScrollBarStyle, String> {
    match name {
        "Default" => Ok(wry::ScrollBarStyle::Default),
        "FluentOverlay" => Ok(wry::ScrollBarStyle::FluentOverlay),
        other => Err(format!("unknown scroll bar style: {other}")),
    }
}

/// wry's proxy for a URL's `scheme`, `host`, and `port`, as
/// `parse_proxy_url` builds it (`src/lib.rs:4301-4316`), or tauri-runtime's
/// `Error::InvalidProxyUrl` message (`lib.rs:161-162`) for any scheme but
/// `http` and `socks5`.
fn proxy_config(scheme: &str, host: String, port: String) -> Result<wry::ProxyConfig, String> {
    let endpoint = wry::ProxyEndpoint { host, port };
    match scheme {
        "http" => Ok(wry::ProxyConfig::Http(endpoint)),
        "socks5" => Ok(wry::ProxyConfig::Socks5(endpoint)),
        _ => Err("Invalid proxy url".to_string()),
    }
}

// SPDX-SnippetEnd

// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: Drag-drop handler pattern adapted from tauri-runtime-wry/lib.rs lines 4669-4703

/// The drag-drop handler of the webview labeled `label`, which Tauri's
/// `create_webview` installs unless the builder disabled it
/// (tauri-runtime-wry `src/lib.rs:4669-4703`). It captures only a proxy and
/// a copy of the label, and sends each event to Ruby through the loop
/// (plan 043; plan 052, decision 2).
fn drag_drop_handler(
    proxy: &RbProxy,
    label: &str,
) -> impl Fn(wry::DragDropEvent) -> bool + 'static {
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
}

// SPDX-SnippetEnd

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
/// The webview is built with the web context of its data directory, as
/// Tauri's `create_webview` builds every webview
/// (tauri-runtime-wry `src/lib.rs:4589-4625`): the context the store holds
/// for that directory, or a new one, lent for the length of the build
/// (`web_context.rs`). On Linux the context keeps the protocols its first
/// webview registered, and a later webview of the same context registers
/// none, as Tauri's runtime skips them (`:4964-4981`); their handlers
/// read each request's webview from the id wry hands them, so each
/// request still names its own webview.
///
/// # Errors
///
/// Returns `ThreadError` off the window's thread, or `RuntimeError` when
/// the window is closed or empty, when another build holds the web
/// context, when wry fails, or on Windows when `WebView2` refuses a focus
/// handler.
fn build(
    window: &RbWindow,
    proxy: &RbProxy,
    label: &str,
    url: String,
    initialization_scripts: Vec<(String, bool)>,
    attributes: &Attributes,
) -> Result<Built, Error> {
    let proxy_clone = proxy.inner().clone();
    let label_for_ipc_message = label.to_string();
    let proxy_for_protocol = proxy.inner().clone();
    let proxy_for_ipc = proxy.inner().clone();
    let proxy_for_page_load = proxy.inner().clone();
    let label_for_page_load = label.to_string();

    let mut lent = Lent::take(attributes.data_directory.clone(), label)
        .map_err(|message| Error::new(runtime_error(), message))?;
    let registers_tokra = lent.registers("tokra");
    let registers_ipc = lent.registers("ipc");
    let mut builder =
        attributes.apply(WebViewBuilder::new_with_web_context(lent.context()).with_id(label));
    // Each script for the main frame only or every frame, in order, as
    // Tauri's `create_webview` adds them (tauri-runtime-wry
    // `src/lib.rs:4958-4961`).
    for (script, for_main_frame_only) in initialization_scripts {
        builder = builder.with_initialization_script_for_main_only(script, for_main_frame_only);
    }
    if let Some(handler) = attributes.drag_drop_handler(|| drag_drop_handler(proxy, label)) {
        builder = builder.with_drag_drop_handler(handler);
    }

    builder = builder.with_url(url);
    if registers_tokra {
        // The tokra:// content protocol: Ruby serves HTML, assets, and Rack.
        builder = builder.with_asynchronous_custom_protocol(
            "tokra".into(),
            move |id, request, responder| {
                forward_request_to_ruby(&proxy_for_protocol, id, &request, responder);
            },
        );
    }
    if registers_ipc {
        // The ipc:// transport: Tauri's desktop-default invoke channel. Same
        // request shape, different scheme; Ruby dispatches on the URI scheme.
        builder = builder.with_asynchronous_custom_protocol(
            "ipc".into(),
            move |id, request, responder| {
                forward_request_to_ruby(&proxy_for_ipc, id, &request, responder);
            },
        );
    }
    let builder = builder
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
    Ok(Built {
        webview,
        _context: lent.built(),
    })
}

/// A built webview and its place in its web context.
///
/// The webview drops first, then the lease, which forgets the webview in
/// the store and drops the context with its last webview (`web_context.rs`),
/// so wry's context outlives every webview built with it, as it must
/// (wry `src/web_context.rs:17-21`).
pub struct Built {
    webview: WebView,
    _context: Lease,
}

impl std::ops::Deref for Built {
    type Target = WebView;

    fn deref(&self) -> &WebView {
        &self.webview
    }
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
    inner: RefCell<ThreadBound<Built>>,
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
            initialization_scripts
                .into_iter()
                .map(|script| (script, true))
                .collect(),
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
    /// `initialization_scripts`, each `[script, for_main_frame_only]` in
    /// order, and the webview rows a `Tokra::WebviewBuilder` sends (see
    /// `Attributes`), into this empty webview, as Tauri's runtime builds a
    /// webview window's webview right after its window (tauri-runtime-wry
    /// `src/lib.rs:4489-4500`). Without `drag_drop_handler_enabled` false
    /// the webview gets the drag-drop handler, as Tauri's does.
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
    /// attribute of the wrong type, `RangeError` for a data store
    /// identifier byte outside 0 to 255 (macOS), `ArgumentError` for a
    /// background throttling policy or scroll bar style no variant names, and
    /// `RuntimeError` "Invalid proxy url" for a proxy of a scheme but
    /// `http` and `socks5`, before building anything; `ThreadError`
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
        let initialization_scripts: Vec<(String, bool)> =
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

    /// The open wry webview handed to `call`, on its own thread, or `None`
    /// once closed or before `open` fills it. wry's error becomes a
    /// `RuntimeError` with its message, which `Tokra::Webview` turns into
    /// the runtime's error or log line.
    ///
    /// So does a panic wry raises at one of `sites`, the unwraps this call
    /// reaches in its own frames (see [`guarded`]): on macOS
    /// `-[WKWebView URL]` and its `absoluteString`
    /// (`src/wkwebview/mod.rs:1245-1246`), the `NSURL` a navigation parses
    /// (`:775`), and the `NSHTTPCookie` a cookie becomes, which is nil for
    /// an empty name or a value holding a newline (`:1082-1083`); on Linux
    /// the `GDateTime` of an expiration before year 1
    /// (`src/webkitgtk/mod.rs:982`). Tauri panics there; across magnus a
    /// panic is a `fatal` Ruby cannot rescue. Each fires in wry's Rust,
    /// after the platform call it unwraps has returned and before the next,
    /// so no foreign frame lies between it and this call, and the webview
    /// is as it was. Any other panic, such as one in a delegate the cookie
    /// spin runs, would have unwound through `CFRunLoop` or `WebKit`, so it
    /// is resumed and stays fatal. Rust's panic hook still prints each.
    ///
    /// The borrow is held for the whole call, which for a cookie call
    /// spins a nested loop (plan 052, decision e2-1). Nothing that runs in
    /// that loop reaches this webview, except under Windows' menu-loop
    /// hook, where a nested `close` fails with `WebView is in use`.
    fn with_open<T>(
        &self,
        sites: &[Site<'_>],
        call: impl FnOnce(&WebView) -> wry::Result<T>,
    ) -> Result<Option<T>, Error> {
        let inner = self
            .inner
            .try_borrow()
            .map_err(|_| Error::new(runtime_error(), "WebView is closing"))?;
        if !inner.owner().is_current() {
            return Err(wrong_thread(CLASS));
        }
        inner
            .get()
            .map(|webview| {
                guarded(sites, || call(webview))
                    .map_err(|message| Error::new(runtime_error(), message))?
                    .map_err(|e| Error::new(runtime_error(), e.to_string()))
            })
            .transpose()
    }

    // SPDX-SnippetBegin
    // SPDX-License-Identifier: Apache-2.0 OR MIT
    // SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    // SPDX-SnippetComment: The webview's Url, Navigate, Reload, and cookie arms adapted from
    //                      tauri-runtime-wry/src/lib.rs handle_user_message
    /// wry's `WebView::url`, the page's address, or `nil` once closed, as
    /// Tauri's runtime answers its `Url` message (`src/lib.rs:3758-3765`).
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the webview's thread, or a `RuntimeError`
    /// with wry's error.
    pub fn url(&self) -> Result<Option<String>, Error> {
        self.with_open(URL_SITES, WebView::url)
    }

    /// wry's `WebView::load_url`, as Tauri's runtime handles `Navigate`
    /// (`src/lib.rs:3647-3651`). A closed webview ignores it.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the webview's thread, or a `RuntimeError`
    /// with wry's error, which `Tokra::Webview` logs.
    pub fn navigate(&self, url: magnus::RString) -> Result<(), Error> {
        let url = url.to_string()?;
        self.with_open(NAVIGATE_SITES, |webview| webview.load_url(&url))
            .map(|_| ())
    }

    /// wry's `WebView::reload`, as Tauri's runtime handles `Reload`
    /// (`src/lib.rs:3652-3656`). A closed webview ignores it.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the webview's thread, or a `RuntimeError`
    /// with wry's error, which `Tokra::Webview` logs.
    pub fn reload(&self) -> Result<(), Error> {
        self.with_open(&[], WebView::reload).map(|_| ())
    }

    /// wry's `WebView::cookies`, as an Array of Hashes, or `nil` once
    /// closed (`src/lib.rs:3768-3771`).
    ///
    /// wry waits for the platform's cookie store on the main thread: on
    /// macOS by running the main `NSRunLoop` in its default mode, two
    /// milliseconds at a time, up to 500 times
    /// (`src/wkwebview/mod.rs:1341-1369`); on Windows by a nested
    /// `GetMessage` loop until `WebView2` answers (webview2-com
    /// `src/lib.rs:60-81`); on Linux by `gtk::main_iteration` until
    /// `WebKitGTK` answers (`src/webkitgtk/mod.rs:1031-1056`). The GVL stays
    /// held. Plan 052, decision e2-1, says why no tao handler and no Ruby
    /// runs inside those loops.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the webview's thread, or a `RuntimeError`
    /// with wry's error, such as macOS's "timed out waiting for cookies
    /// response".
    pub fn cookies(ruby: &Ruby, rb_self: &Self) -> Result<Option<magnus::RArray>, Error> {
        rb_self
            .with_open(&[], WebView::cookies)?
            .map(|cookies| crate::cookie::cookies_to_array(ruby, &cookies))
            .transpose()
    }

    /// wry's `WebView::cookies_for_url`, as `cookies` answers
    /// (`src/lib.rs:3785-3790`).
    ///
    /// # Errors
    ///
    /// As `cookies`.
    pub fn cookies_for_url(
        ruby: &Ruby,
        rb_self: &Self,
        url: magnus::RString,
    ) -> Result<Option<magnus::RArray>, Error> {
        let url = url.to_string()?;
        rb_self
            .with_open(&[], |webview| webview.cookies_for_url(&url))?
            .map(|cookies| crate::cookie::cookies_to_array(ruby, &cookies))
            .transpose()
    }

    /// wry's `WebView::set_cookie` with the cookie `Tokra::Cookie` sends
    /// as `fields`, as Tauri's runtime handles `SetCookie`
    /// (`src/lib.rs:3773-3777`). A closed webview ignores it. On macOS and
    /// Linux wry waits for the store as `cookies` does.
    ///
    /// # Errors
    ///
    /// Returns the errors `cookie::cookie_from_hash` gives for a malformed
    /// Hash, before anything else; `ThreadError` off the webview's thread;
    /// or a `RuntimeError` with wry's error, which `Tokra::Webview` logs.
    pub fn set_cookie(ruby: &Ruby, rb_self: &Self, fields: magnus::RHash) -> Result<(), Error> {
        let cookie = crate::cookie::cookie_from_hash(ruby, fields)?;
        rb_self
            .with_open(COOKIE_SITES, |webview| webview.set_cookie(&cookie))
            .map(|_| ())
    }

    /// wry's `WebView::delete_cookie`, as `set_cookie` runs, as Tauri's
    /// runtime handles `DeleteCookie` (`src/lib.rs:3779-3783`).
    ///
    /// # Errors
    ///
    /// As `set_cookie`.
    pub fn delete_cookie(ruby: &Ruby, rb_self: &Self, fields: magnus::RHash) -> Result<(), Error> {
        let cookie = crate::cookie::cookie_from_hash(ruby, fields)?;
        rb_self
            .with_open(COOKIE_SITES, |webview| webview.delete_cookie(&cookie))
            .map(|_| ())
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
        Ok(std::cell::Ref::filter_map(inner, |inner| inner.get().map(|built| &built.webview)).ok())
    }
}

/// Where in wry's locked source a panic is raised: the end of the file's
/// path, with `/` between its parts, and the line. wry's unwraps are
/// `#[track_caller]`, so the location a panic reports is wry's own line.
#[derive(Debug, Clone, Copy)]
struct Site<'a> {
    file: &'a str,
    line: u32,
}

/// wry's macOS backend, at the version `Cargo.lock` holds.
const WKWEBVIEW: &str = "wry-0.54.1/src/wkwebview/mod.rs";

/// `url_from_webview`'s two unwraps (`src/wkwebview/mod.rs:1245-1246`).
const URL_SITES: &[Site<'static>] = &[
    Site {
        file: WKWEBVIEW,
        line: 1245,
    },
    Site {
        file: WKWEBVIEW,
        line: 1246,
    },
];

/// `navigate_to_url`'s `NSURL` unwrap (`src/wkwebview/mod.rs:775`).
const NAVIGATE_SITES: &[Site<'static>] = &[Site {
    file: WKWEBVIEW,
    line: 775,
}];

/// `cookie_into_wkwebview`'s expect (`src/wkwebview/mod.rs:1082-1083`)
/// and `cookie_into_soup_cookie`'s `GDateTime` unwrap
/// (`src/webkitgtk/mod.rs:982`). Each runs before the call waits for the
/// store, and nothing else reaches it.
const COOKIE_SITES: &[Site<'static>] = &[
    Site {
        file: WKWEBVIEW,
        line: 1083,
    },
    Site {
        file: "wry-0.54.1/src/webkitgtk/mod.rs",
        line: 982,
    },
];

thread_local! {
    /// Where the last panic on this thread was raised, as the hook
    /// [`guarded`] installs records it.
    static LAST_PANIC: std::cell::RefCell<Option<(String, u32)>> =
        const { std::cell::RefCell::new(None) };
}

/// Puts a panic hook in front of whichever one is set, once, that records
/// each panic's location for [`guarded`] and then runs the one before it,
/// so a panic still prints as it did.
///
/// `define_class` calls it from `Init_tokra`, where no other Ruby thread
/// runs Tokra's code yet, so no hook another thread sets can fall between
/// `take_hook` and `set_hook`; `guarded` calls it too, in case it runs
/// first, as in a Rust test. What remains is an extension that sets a
/// hook after this one: that disables the recording, so every panic is
/// resumed, which is the safe side.
fn record_panic_sites() {
    static INSTALL: std::sync::Once = std::sync::Once::new();
    INSTALL.call_once(|| {
        let previous = std::panic::take_hook();
        std::panic::set_hook(Box::new(move |info| {
            if let Some(location) = info.location() {
                let site = (location.file().replace('\\', "/"), location.line());
                let _ = LAST_PANIC.try_with(|last| {
                    if let Ok(mut last) = last.try_borrow_mut() {
                        *last = Some(site);
                    }
                });
            }
            previous(info);
        }));
    });
}

/// `call`'s answer, or the message of a panic it raised at one of `sites`.
/// A panic raised anywhere else is resumed.
///
/// Matching on the place, not the message, tells a panic in the calling
/// frames from one in a delegate or a completion block the platform ran
/// meanwhile: wry's delegates and blocks are `C-unwind` (objc2 0.6.3
/// `src/__macro_helpers/define_class.rs:1279`; block2 0.6.2
/// `src/abi.rs:239`), so such a panic would arrive here through
/// `CFRunLoop` and `WebKit`, and a message like "called `Option::unwrap()`
/// on a `None` value" could come from either. Each call names only the
/// sites its own frames reach before or without spinning a loop.
///
/// # Panics
///
/// Resumes any panic not raised at one of `sites`.
fn guarded<T>(sites: &[Site<'_>], call: impl FnOnce() -> T) -> Result<T, String> {
    record_panic_sites();
    LAST_PANIC.with(|last| last.borrow_mut().take());
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(call)).map_err(|panic| {
        let raised = LAST_PANIC.with(|last| last.borrow().clone());
        let known = raised.is_some_and(|(file, line)| {
            sites
                .iter()
                .any(|site| site.line == line && file.ends_with(site.file))
        });
        if !known {
            std::panic::resume_unwind(panic);
        }
        panic_message(&*panic)
    })
}

/// The message a caught panic carries: the `&str` or `String` that
/// `panic!`, `unwrap`, and `expect` give it, or a fixed one for anything
/// else.
fn panic_message(panic: &(dyn std::any::Any + Send)) -> String {
    panic
        .downcast_ref::<&str>()
        .map(|message| (*message).to_owned())
        .or_else(|| panic.downcast_ref::<String>().cloned())
        .unwrap_or_else(|| "wry panicked".to_owned())
}

/// Define the `WebView` class methods on the given Ruby module.
///
/// # Errors
///
/// Returns an error if class or method definition fails.
pub fn define_class(ruby: &Ruby, native: magnus::RModule) -> Result<(), Error> {
    record_panic_sites();
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
    webview_class.define_method("url", method!(RbWebView::url, 0))?;
    webview_class.define_method("navigate", method!(RbWebView::navigate, 1))?;
    webview_class.define_method("reload", method!(RbWebView::reload, 0))?;
    webview_class.define_method("cookies", method!(RbWebView::cookies, 0))?;
    webview_class.define_method("cookies_for_url", method!(RbWebView::cookies_for_url, 1))?;
    webview_class.define_method("set_cookie", method!(RbWebView::set_cookie, 1))?;
    webview_class.define_method("delete_cookie", method!(RbWebView::delete_cookie, 1))?;
    #[cfg(windows)]
    webview_class.define_method("set_theme", method!(RbWebView::set_theme, 1))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{
        background_throttling, http_request_event, panic_message, proxy_config, Attributes,
        UserEvent,
    };

    #[test]
    fn a_panic_at_a_known_site_is_its_message_and_any_other_is_resumed() {
        let raise = || {
            std::hint::black_box(None::<()>)
                .expect("failed to create wkwebview cookie, report this as bug to `wry`");
        };
        // With no known site the panic is resumed, and the hook has
        // recorded where it was raised.
        let resumed = std::panic::catch_unwind(|| super::guarded(&[], raise)).unwrap_err();
        let (file, line) = super::LAST_PANIC
            .with(|last| last.borrow().clone())
            .unwrap();
        let elsewhere = super::Site {
            file: &file,
            line: line + 1,
        };
        let resumed_again =
            std::panic::catch_unwind(|| super::guarded(&[elsewhere], raise)).unwrap_err();
        let converted = super::guarded(&[super::Site { file: &file, line }], raise);

        assert!(file.ends_with("src/webview.rs"), "{file}");
        assert_eq!(
            panic_message(&*resumed),
            "failed to create wkwebview cookie, report this as bug to `wry`"
        );
        assert_eq!(
            panic_message(&*resumed_again),
            panic_message(&*resumed),
            "another line is another site"
        );
        assert_eq!(
            converted,
            Err("failed to create wkwebview cookie, report this as bug to `wry`".into())
        );
        assert_eq!(super::guarded(&[], || 5), Ok(5));
    }

    #[test]
    fn a_caught_panic_reads_as_the_message_wry_gave_it() {
        // A `None` the compiler cannot see through, as wry's are.
        let none = || std::hint::black_box(None::<()>);
        let expected = std::panic::catch_unwind(|| {
            none().expect("failed to create wkwebview cookie, report this as bug to `wry`");
        })
        .unwrap_err();
        let unwrapped = std::panic::catch_unwind(|| none().unwrap()).unwrap_err();
        let formatted = std::panic::catch_unwind(|| panic!("{} {}", "a", 1)).unwrap_err();
        let other = std::panic::catch_unwind(|| std::panic::panic_any(5)).unwrap_err();

        assert_eq!(
            panic_message(&*expected),
            "failed to create wkwebview cookie, report this as bug to `wry`"
        );
        assert_eq!(
            panic_message(&*unwrapped),
            "called `Option::unwrap()` on a `None` value"
        );
        assert_eq!(panic_message(&*formatted), "a 1");
        assert_eq!(panic_message(&*other), "wry panicked");
    }

    #[test]
    fn the_drag_drop_handler_is_built_unless_a_row_turned_it_off() {
        let installed = |enabled: Option<bool>| {
            let attributes = Attributes {
                drag_drop_handler_enabled: enabled,
                ..Attributes::default()
            };
            let mut built = false;
            let handler = attributes.drag_drop_handler(|| {
                built = true;
                "handler"
            });
            (handler, built)
        };
        assert_eq!(
            installed(None),
            (Some("handler"), true),
            "Tauri's default installs it"
        );
        assert_eq!(installed(Some(true)), (Some("handler"), true));
        assert_eq!(
            installed(Some(false)),
            (None, false),
            "disable_drag_drop_handler builds none"
        );
    }

    #[test]
    fn a_proxy_is_http_connect_or_socks5_as_parse_proxy_url_reads_it() {
        match proxy_config("http", "proxy.test".into(), "3128".into()) {
            Ok(wry::ProxyConfig::Http(endpoint)) => {
                assert_eq!(
                    (endpoint.host.as_str(), endpoint.port.as_str()),
                    ("proxy.test", "3128")
                );
            }
            other => panic!("expected an HTTP proxy, got {other:?}"),
        }
        match proxy_config("socks5", "127.0.0.1".into(), String::new()) {
            Ok(wry::ProxyConfig::Socks5(endpoint)) => {
                assert_eq!(
                    (endpoint.host.as_str(), endpoint.port.as_str()),
                    ("127.0.0.1", "")
                );
            }
            other => panic!("expected a SOCKSv5 proxy, got {other:?}"),
        }
        for scheme in ["https", "socks4", "HTTP", ""] {
            assert_eq!(
                proxy_config(scheme, "proxy.test".into(), "1".into())
                    .err()
                    .as_deref(),
                Some("Invalid proxy url"),
                "{scheme:?} is refused with tauri-runtime's message"
            );
        }
    }

    #[test]
    fn each_policy_name_is_its_wry_policy() {
        assert!(matches!(
            background_throttling("Disabled"),
            Ok(wry::BackgroundThrottlingPolicy::Disabled)
        ));
        assert!(matches!(
            background_throttling("Suspend"),
            Ok(wry::BackgroundThrottlingPolicy::Suspend)
        ));
        assert!(matches!(
            background_throttling("Throttle"),
            Ok(wry::BackgroundThrottlingPolicy::Throttle)
        ));
        assert_eq!(
            background_throttling("Off").err().as_deref(),
            Some("unknown background throttling policy: Off")
        );
    }

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
