<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Tauri's event system: `Listener` (`listen`, `once`, `unlisten`,
  `listen_any`, `once_any`) and `Emitter` (`emit`, `emit_str`, `emit_to`,
  `emit_str_to`, `emit_filter`, `emit_str_filter`) on `App`, `AppHandle`,
  `Window`, and `Webview`, with `Tokra::Event`, `Tokra::EventTarget`, and
  `Error::IllegalEventName`
- The `event` core plugin, so `listen`, `once`, `emit`, and `emitTo` from
  `@tauri-apps/api/event` reach Ruby and hear it
- `Window#on_window_event`, and `Builder#on_window_event`, whose blocks receive
  the `Tokra::Window` and each `WindowEvent` after the run callback, except
  `CloseRequested`, which they hear first
- `WindowEvent::Resized(size)`, `Moved(position)`, `Focused`,
  `ScaleFactorChanged(scale_factor, new_inner_size)`, `ThemeChanged(theme)`,
  `DragDrop(event)`, `CloseRequested`, and `Destroyed`, delivered to
  `RunEvent::WindowEvent`, `on_window_event` blocks, and the page as
  `tauri://resize`, `tauri://move`, `tauri://focus`, `tauri://blur`,
  `tauri://scale-change`, `tauri://theme-changed`, `tauri://drag-enter`,
  `-over`, `-drop`, `-leave`, `tauri://close-requested`, and
  `tauri://destroyed`; drops on the window's webview are the window's, as in
  Tauri, and a page listening for `tauri://close-requested` on its window
  keeps it open when it is asked to close
- `Plugin#on_event(app, event)`, `Plugin#window_created(window)`, and
  `Plugin#webview_created(webview)` hooks; the created hooks hear every
  window and webview the app makes, `main` included, on the main thread,
  with `PluginStore#window_created` and `#webview_created`
- `Tokra::WebviewWindowBuilder.new(manager, label, url)` with Tauri's desktop
  rows (`#title`, `#inner_size`, `#menu`, `#on_menu_event`, `#center`,
  `#position`, `#min_inner_size`, `#max_inner_size`, `#inner_size_constraints`,
  `#prevent_overflow`, `#prevent_overflow_with_margin`, `#resizable`,
  `#maximizable`, `#minimizable`, `#closable`, `#fullscreen`, `#focus`
  (deprecated), `#focused`, `#focusable`, `#maximized`, `#visible`, `#theme`,
  `#decorations`, `#always_on_bottom`, `#always_on_top`,
  `#visible_on_all_workspaces`, `#content_protected`, `#icon`, `#skip_taskbar`,
  `#window_classname`, `#shadow`, `#parent`, `#effects`, `#background_color`;
  `#transparent` off macOS; `#owner` and `#drag_and_drop` on Windows;
  `#transient_for` on Linux; `#title_bar_style`, `#hidden_title`,
  `#tabbing_identifier`, and `#traffic_light_position` on macOS) and Tauri's
  defaults (focused; on macOS the `Visible` title bar over a full-size content
  view, so every window's inner size, `main`'s included, takes in its title
  bar and the page is about 32 points shorter; on Windows the window
  class "Tokra Window", and a WebView2 in its window's theme), and `#build`, which
  makes a window and its webview at run
  time from any thread: at once on the main thread, and from another thread
  queued ahead of every later call on it; a native failure is warned, not
  raised, with Tauri's "failed to create window" or "failed to create
  webview: ...", and does not keep the app from exiting. The windows the config's `app.windows` lists are built this way before the
  setup hook, so the hook finds them
- `Tokra::WebviewWindowBuilder.from_config(manager, config)`, and the config's
  windows take every row of their `WindowConfig` the builder has
- `Error::WindowNotFound`, "window not found", for a config window whose
  `parent` names no window
- `WebviewWindowBuilder`'s webview rows from Tauri's `WebviewBuilder`:
  `#accept_first_mouse`, `#initialization_script`,
  `#initialization_script_for_all_frames`, `#user_agent`,
  `#additional_browser_args`, `#disable_drag_drop_handler`,
  `#enable_clipboard_access`, `#incognito`, `#proxy_url` (a
  `Ferro::Url::Url`, `http://` or `socks5://`; any other scheme warns
  "Invalid proxy url"; ignored on macOS, as in Tauri without
  `macos-proxy`), `#browser_extensions_enabled`,
  `#extensions_path`, `#data_store_identifier`, `#background_throttling`,
  `#disable_javascript`, `#scroll_bar_style`, and on macOS
  `#allow_link_preview`, each with Tauri's default
- `Tokra::BackgroundThrottlingPolicy` (`Disabled`, `Suspend`, `Throttle`) and
  `Tokra::ScrollBarStyle` (`Default`, and on Windows `FluentOverlay`)
- `Webview#url`, `#navigate`, `#reload`, `#cookies`, `#cookies_for_url`,
  `#set_cookie`, and `#delete_cookie`, the same on `WebviewWindow`, each URL
  a `Ferro::Url::Url`, with
  `Tokra::Cookie` (and its `SameSite` and `Expiration`) and
  `Error::InvalidUrl`; a failed navigation, reload, or cookie write is
  logged in Tauri's words, and where wry panics (some cookies on macOS
  and Linux) the call raises or logs wry's message instead
- `Tokra::WebviewWindow`, a window and its webview as one object, with
  Tauri's window, webview, `Listener`, `Emitter`, and `Manager` methods;
  `Manager#get_webview_window`, `#webview_windows`, and
  `#get_focused_window`; `Webview#cursor_position`; and
  `Ipc::Invoke#webview_window`
- `Tokra::WebviewUrl::App`, `External`, and `CustomProtocol`, the page a new
  webview opens; `External` and `CustomProtocol` hold a frozen
  `Ferro::Url::Url`, and an `App` path joins `tokra://localhost/`
  (`http://tokra.localhost/` on Windows) as the url crate joins it
- Window labels follow Tauri's rule: a label with any character but a
  letter, a digit, `-`, `/`, `:`, or `_` raises `Error::Runtime`, and a
  taken one `Error::WebviewLabelAlreadyExists` or
  `Error::WindowLabelAlreadyExists`, the webview's checked first
- `tauri://webview-created` and then `tauri://window-created`, each with
  `{"label": ...}`, for every window the app makes
- `Native::Window.empty(proxy)`, `Native::Window#open(event_loop, label,
  attributes)`, `Native::Window#discard`, `Native::WebView.empty(proxy)`, and
  `Native::WebView#open(window, proxy, label, attributes)`, each `attributes` a
  Hash of a builder's rows; the webview's `initialization_scripts` are
  `[script, for_main_frame_only]` pairs
- `Tokra::Ipc::Invoke`, whose responders receive the response as JSON text; a
  value JSON cannot encode rejects the invoke with the serializer's message
- `Window#set_title`, `Window#set_size`, `Webview#eval`, and `AppHandle#emit`
  called from another thread run on the main thread and return `nil` without
  waiting, as in Tauri; `Webview#eval` logs a script the webview fails to
  evaluate instead of raising; `Window#title` on a closed window raises
  `Error::Runtime` (`failed to receive message from webview`)
- `Native::WindowResizedEvent`, `WindowMovedEvent`, `WindowFocusedEvent`,
  `WindowScaleFactorChangedEvent`, and `WindowThemeChangedEvent`, each
  carrying its window's label; `Native::DragDropEvent` and, on Windows,
  `Native::WebviewFocusedEvent`, each carrying its webview's label; and
  `Native::WebView#set_theme` (Windows)
- `Builder#on_page_load`'s block receives the `Webview` that loaded the
  page, and each plugin's `Plugin#on_page_load` hears the load after it;
  the payload's `url` is a `Ferro::Url::Url`, and a load whose URL the url
  crate refuses is not reported
- Dependency: webview2-com 0.38.2 on Windows
- `Tokra::Webview` wrapper class with per-webview `ResourceTable`
- `Tokra::Window` wrapper class with per-window `ResourceTable`
- `Tokra::ResourceTable` with full lifecycle management:
  - `add(resource)` returns unique integer ID
  - `get(rid)` retrieves resource by ID
  - `take(rid)` removes without calling close
  - `close(rid)` removes and calls resource.close
  - `replace(rid, resource)` updates existing slot
  - `clear` removes all resources
  - `names` enumerator for debugging
- `Tokra::Resource` mixin module (mirrors Tauri's Resource trait)
- `Tokra::Image` data class for RGBA images with ResourceTable integration
- `Tokra::Error` base class with nested `BadResourceId` exception
- `Invoke#webview` returns the calling webview
- `AppHandle#windows` returns all managed windows
- `AppHandle#get_window(label)` fetches window by label
- `AppHandle#get_webview(label)` fetches webview by label
- `AppHandle#resources_table` returns app-level fallback table
- `Manager#resources_table` abstract method for unified interface
- `App`, `Window`, and `Webview` are full `Manager`s, as in Tauri: `manage`,
  `state`, `try_state`, `config` (Tauri's whole config), `package_info`, and
  the window and webview lookups reach the app from whichever handle you hold; `Window#webviews` answers that window's
  own webviews as an Array, as Tauri's does
- `Tokra::PluginStore` routes `plugin:NAME|command` invokes to the named plugin
- `AppHandle#plugin(plugin)` registers a plugin for IPC dispatch
- `AppHandle#remove_plugin(name)` unregisters a plugin by name
- Plugin `extend_api` receives the bare command name (prefix stripped)
- Unhandled IPC commands are rejected with `Command <name> not found`
- Core `resources` plugin, registered automatically:
  - `plugin:resources|close` closes a resource (webview, then window, then app),
    rejecting a `rid` that is not a u32 with Tauri's `invalid args` message
- Core `image` plugin, registered automatically:
  - `plugin:image|new` stores an RGBA image and resolves its resource ID
  - `plugin:image|rgba` resolves the stored image's bytes
  - `plugin:image|size` resolves the stored image's width and height
  - `plugin:image|from_bytes` decodes PNG or ICO bytes into a stored image
  - `plugin:image|from_path` decodes a PNG or ICO file into a stored image
  - each argument reads as its Rust type, so one that does not (a byte
    outside 0 to 255, or a size or ID outside u32) rejects with Tauri's
    `invalid args` message
- `Tokra::Image.from_bytes` decodes PNG or ICO bytes to raw RGBA
- `Tokra::Image.from_path` decodes a PNG or ICO file (a path String or
  anything with `to_path`) to raw RGBA, raising
  `Tokra::Error::Io` (Tauri's `Error::Io`) when the file cannot be read,
  with Rust's `std::io::Error` message, such as `No such file or directory
  (os error 2)` (on Windows, the Win32 error's text)
- `Tokra::Error::Image` raised when image bytes cannot be decoded
- `Tokra::JsImage.deserialize` reads a frontend image payload (file path,
  byte array, resource ID, or RGBA hash) as Tauri does, raising
  `CommandItem::Mismatch` for any other value, and `JsImage#into_img`
  resolves it into a `Tokra::Image`
- Registered plugins receive `RunEvent::Ready`, `RunEvent::WindowEvent`
  (close requested and destroyed), `RunEvent::ExitRequested`, and
  `RunEvent::Exit` through `Plugin#on_event`, before the run callback;
  `Exit` is emitted from the native loop's `Native::LoopDestroyedEvent`,
  since tao's event loop never returns, and a `Kernel#exit` in its handler
  sets the process's exit status
- Frontend `invoke` promises resolve and reject: `App` evaluates Tauri's
  `runCallback` in the WebView, so `@tauri-apps/api` works end to end
- `Tokra::Ipc::FormatCallback` formats invoke responses as callback scripts
- Injected `__TAURI_INTERNALS__` initialization scripts (vendored from Tauri
  via `rake sync:tauri`), guarded by a per-app invoke key
- `Tokra.generate_invoke_key` returns a Z85-encoded random invoke key
- `Builder#app(rack_app)` serves a Rack application over the `tokra://` protocol
- `ipc://` IPC transport (Tauri's desktop-default invoke channel), served as a
  second custom protocol; `postMessage` is retained as the automatic fallback
- Both IPC transports read invoke bodies as Tauri's serde_json does: a body it
  rejects (invalid UTF-8 or a lone surrogate escape in a string, a comment, a
  number out of range, nesting past 127 levels, a non-string `cmd`) never
  reaches a command, and fails with serde_json's message (`ipc://` answers
  500, `postMessage` evaluates `console.error("JSON error: ...")`); payloads
  hold serde_json's values, so `-0` and integers outside 64 bits are floats
  and object keys come in byte order
- An `ArrayBuffer` or typed array invoke reaches the command over `ipc://`
  as a binary String, unparsed
- `Invoke#payload` is the body as sent, any JSON value or bytes;
  `Invoke#body` is the same value
- `Invoke#headers`: every `ipc://` request header, or a `postMessage`'s
  `options.headers`, with lowercase names
- `Tokra::Ipc::Request.from_command(invoke)`, Tauri's `ipc::Request`, with
  `body` and `headers`
- `Tokra::Ipc::Response.new(string)`, Tauri's `ipc::Response`: a binary
  String resolves the invoke with an `ArrayBuffer` (a number array over
  `postMessage` on macOS or after `ipc://` failed), other text is sent as
  JSON text in UTF-8; off macOS a hand-sent `postMessage`'s object, array,
  or raw result reaches the page over a Channel, as in Tauri
- `Tokra::Ipc::InvokeBody.raw?` tells raw bytes from JSON
- A `postMessage` whose `options.headers` the http crate refuses is
  reported with `console.error("JSON error: ...")` and not dispatched
- The config's `app.withGlobalTauri` injects the vendored `@tauri-apps/api`
  bundle as `window.__TAURI__`, so a page with no frontend bundler calls
  `window.__TAURI__.core.invoke(...)` directly, as in Tauri
- `Plugin#initialization_script` is injected into every page after Tauri's
  init scripts, wrapped in an IIFE, in each webview made after the plugin
  is registered, so register a plugin before `App#run` for the config's
  windows;
  `PluginStore#initialization_script` collects them
- `AppHandle#manage(state)` stores managed state and returns whether it did
- `Native::Proxy#drop_response(request_id)` closes a pending protocol request
  without a reply
- `Native::LoopDestroyedEvent`, delivered as the native event loop ends
- `Native::EventLoop.gvl_handoff_counts`, how often the loop has handed the
  GVL to other Ruby threads, at the end of a turn and inside a Windows menu
- `Native::IpcEvent#url`, the URL of the frame that posted the message
- `Rack::Handler::Tokra.run` accepts `native:`, like `Builder#run`
- `tokra-clipboard` gem: `Tokra::Plugins::Clipboard::Plugin.new(app)` manages
  a `Tokra::Plugins::Clipboard::Clipboard` on the app handle (reachable as
  `app.clipboard`, Ractor-shareable) and serves Tauri's `clipboard-manager`
  commands (`read_text`, `write_text`, `read_image`, `write_image`,
  `write_html`, `clear`); every failure raises or rejects with
  `Error::Clipboard` or Tauri's argument error, and `read_text` raises on an
  empty clipboard; it is pure Ruby and depends on `ferro-arboard`
  0.1.0.pre.2 (arboard 3.7.0, Wayland included), which apps take from its
  git tag until it is on RubyGems.org
- `tokra-dialog` gem: `Tokra::Plugins::Dialog::Plugin.new(app)` manages a
  `Tokra::Plugins::Dialog::Dialog` (reachable as `app.dialog`) with Tauri's
  `MessageDialogBuilder` and `FileDialogBuilder`, serves Tauri's dialog
  commands (`open`, `save`, `message`, `ask`, `confirm`) for
  `@tauri-apps/plugin-dialog`, and replaces the page's `window.alert` and
  `window.confirm` with them; dialogs start on the main thread and are
  awaited off it, so the window keeps running; the builders' `set_parent`
  and `parent` take a `Tokra::Window`, and the commands parent each dialog
  to the calling window as Tauri does, except on Wayland (ferro-rfd binds
  no Wayland handle), so on macOS each is a sheet on that window; picked
  paths join no scope; it is pure Ruby and depends on `ferro-rfd`
  0.1.0.pre.3 (rfd 0.17.2), which apps take from its git tag until it is
  on RubyGems.org
- `tokra-notification` gem: `Tokra::Plugins::Notification::Plugin.new(app)`
  manages a `Tokra::Plugins::Notification::Notification` (reachable as
  `app.notification`) with Tauri's `NotificationBuilder`, serves Tauri's
  desktop notification commands (`notify`, `request_permission`,
  `is_permission_granted`) for `@tauri-apps/plugin-notification` with
  Tauri's argument errors, and backs the page's `window.Notification`;
  permission is always granted, a notification shows its title (or the
  product name), body, icon, and sound, and goes out on its own thread;
  macOS names the app by its identifier, Windows names none; an
  `Attachment` holds its URL as a `Ferro::Url::Url`, and `Schedule::At`
  its date as a `Ferro::Time::OffsetDateTime`; it is pure Ruby and
  depends on `ferro-notify-rust` 0.1.0.pre.4 (notify-rust 4.18.2),
  `ferro-url` 0.1.0.pre.1 (url 2.5.8), and `ferro-time` 0.1.0.pre.4 (time
  0.3.55), which apps take from their git tags until they are on
  RubyGems.org
- `Tokra::PermissionState` (`Granted`, `Denied`, `Prompt`,
  `PromptWithRationale`), Tauri's `tauri::plugin::PermissionState`
- `tokra-global-shortcut` gem: `Tokra::Plugins::GlobalShortcut::Plugin.new(app)`
  (or `Builder` with `with_shortcut`, `with_shortcuts`, `with_handler`, and
  `build(app)`) manages a `GlobalShortcut` (reachable as
  `app.global_shortcut`) with Tauri's `register`, `on_shortcut`,
  `register_multiple`, `on_shortcuts`, `unregister`, `unregister_multiple`,
  `unregister_all`, and `is_registered`, and serves Tauri's commands for
  `@tauri-apps/plugin-global-shortcut`, sending each press through the
  page's Channel; handlers run on a thread of their own; it is pure Ruby and
  depends on `ferro-global-hotkey` 0.1.0.pre.1 (global-hotkey 0.9.0), which
  apps take from Ferro's git repository until it is on RubyGems.org
- `Tokra::Ipc::Channel` and `Tokra::Ipc::JavaScriptChannelId`, Tauri's
  `ipc::Channel`: read a page's Channel argument with
  `Channel.from_command(invoke, key)` and `send` it JSON values, or bytes in
  a `Tokra::Ipc::Response`, which the page receives as an `ArrayBuffer`;
  JSON of 8 KiB or more and bytes of 1 KiB or more wait in the app's
  `Tokra::Ipc::ChannelDataIpcQueue` until the page fetches them with
  Tauri's core `plugin:__TAURI_CHANNEL__|fetch` command, registered on
  every app and exempt from the local-origin check
- `Tokra::Ipc::CommandItem` reads one argument of a command as Tauri's
  `CommandItem` does: `string`, `strings`, and `u32`, or any type through
  `deserialize` and `deserialize_option` with a block that raises
  `CommandItem::Mismatch`, and `CommandItem.integer` reads a u8, u32, or
  i32 with serde's messages, and fails every argument of a raw body with
  Tauri's `bytes payload` message; `Tokra::Ipc::Unexpected` describes a JSON
  value as serde_json's errors do
- `Tokra::Error::InvalidArgs`, Tauri's `invalid args` error, which
  `CommandItem` and `Channel.from_command` raise for an argument that does
  not read, and `Tokra::Ipc::InvokeError`, which `Channel.from_command`
  raises for a string that is not a channel; plugins reject the invoke for
  these and let any other `ArgumentError` reach the router
- `Tokra::Error::PluginInitialization`, Tauri's `failed to initialize plugin`
  error
- `tokra-log` gem: `Tokra::Plugins::Log::Builder` builds a logging plugin
  with Tauri's log targets (standard output, files, the app log directory,
  the webview), rotation and timezone strategies, and RBS signatures
- `run_on_main_thread` on `AppHandle`, `App`, `Window`, and `Webview` runs a
  block on the main thread: at once there, or queued from any other thread
- `Window#title`, answered on the main thread
- `Tokra::Error::Runtime` (`runtime error: failed to send message to the
  webview` / `failed to receive message from webview`), raised when a call
  from another thread cannot reach the main thread or gets no answer
- `Native::Window#title`, `Native::Proxy#send_task`, and `Native::TaskEvent`
- `Window#window_handle`, `Window#display_handle`, `AppHandle#display_handle`,
  and `App#display_handle`, Tauri's `HasWindowHandle` and `HasDisplayHandle`:
  the window's and display's native handles as `Tokra::RawWindowHandle`
  values (`Win32WindowHandle`, `AppKitWindowHandle`, `XlibWindowHandle`,
  `WaylandWindowHandle`, and their display handles; `AppKitWindowHandle`
  adds the window's `window_number` to raw-window-handle's `ns_view`),
  read on the main thread, raising
  `RawWindowHandle::HandleError::Unavailable` from another thread once the
  event loop has ended; on X11 every display handle is the first one tao
  opened
- `Native::Window#raw_window_handle` and `Native::Window#raw_display_handle`
- `App#set_activation_policy` and `Tokra::ActivationPolicy` (`Regular`,
  `Accessory`, `Prohibited`), on macOS only, as in Tauri: set before the
  event loop runs, such as in the setup hook; a `Prohibited` app never
  becomes the active app or takes the keyboard
- `Native::EventLoop#set_activation_policy`, on macOS only
- `Window#set_always_on_top` and `Window#set_ignore_cursor_events`, with
  `Native::Window#set_always_on_top` and `Native::Window#set_ignore_cursor_events`
- `RunEvent::ExitRequested` is emitted when the last window closes (`code`
  is `nil`) and for `AppHandle#exit` (`code` is its code), before
  `RunEvent::Exit`; its `api`, a `Tokra::ExitRequestApi`, has
  `prevent_exit`, which keeps the app running with no window
- `AppHandle#exit` asks through the event loop and returns `nil`; the
  process ends with its code unless a handler prevents the exit, and it
  falls back to `Kernel.exit` once the loop has ended
- `Tokra::RESTART_EXIT_CODE`; `prevent_exit` is ignored for it
- `AppHandle#request_restart` asks to exit with `RESTART_EXIT_CODE` and,
  after `RunEvent::Exit`, runs the app again in a new process and exits
  with 0; `AppHandle#restart` does the same from another thread and never
  returns, and on the main thread restarts at once without
  `RunEvent::ExitRequested`
- `Tokra::Env` and `Manager#env`: the interpreter, the absolute script
  path, and the arguments the app started with, captured when Tokra loads
- `Tokra::Process.current_binary` (the canonical Ruby interpreter, refused
  on macOS when a symlink leads to it) and `Tokra::Process.restart`, which
  refuses an app with no script file (`ruby -e`, standard input)
- `WindowEvent::CloseRequested#api`, a `Tokra::CloseRequestApi`, whose
  `prevent_close` keeps the window open
- `WindowEvent::Destroyed` is emitted once a closed window is gone
- `Window#close` asks to close the window as its close button does, and
  `Window#destroy` closes it without asking
- `Native::Proxy#request_exit` and `#request_close(label)`, which names the
  window to close, `Native::Window#close`, `Native::WebView#close`,
  `Native::WindowDestroyedEvent`, carrying its window's label, and
  `Native::ExitRequestedEvent`
- `Window` getters: `scale_factor`, `inner_position`, `outer_position`,
  `inner_size`, `outer_size`, `is_fullscreen`, `is_minimized`,
  `is_maximized`, `is_focused`, `is_decorated`, `is_resizable`,
  `is_always_on_top`, `is_maximizable`, `is_minimizable`, `is_closable`,
  `is_visible`, `theme`, `current_monitor`, `primary_monitor`,
  `monitor_from_point`, and `available_monitors`; a closed window raises
  `Error::Runtime` (`failed to receive message from webview`)
- `Window` setters: `center`, `request_user_attention`, `set_resizable`,
  `set_maximizable`, `set_minimizable`, `set_closable`, `maximize`,
  `unmaximize`, `minimize`, `unminimize`, `show`, `hide`,
  `set_decorations`, `set_always_on_bottom`,
  `set_visible_on_all_workspaces`, `set_content_protected`, `set_size`
  (a `Tokra::LogicalSize` or `Tokra::PhysicalSize`, as Tauri's takes),
  `set_min_size`, `set_max_size`, `set_position`, `set_fullscreen`,
  `set_simple_fullscreen`, `set_focus`, `set_focusable`,
  `set_skip_taskbar`, `set_cursor_grab`, `set_cursor_visible`,
  `set_cursor_icon`, `set_cursor_position`, `start_dragging`,
  `start_resize_dragging`, and `set_theme`
- `Tokra::LogicalPosition`, `Tokra::LogicalSize`, `Tokra::PhysicalSize`,
  and `Tokra::PhysicalRect`, with dpi's `to_physical`, `to_logical`,
  `from_physical`, and `from_logical` (also on `Tokra::PhysicalPosition`),
  and `Tokra::Dpi.validate_scale_factor`
- `Tokra::Monitor`, `Tokra::Theme`, `Tokra::CursorIcon`,
  `Tokra::UserAttentionType`, and `Tokra::ResizeDirection`
- `to_json` on `PhysicalPosition`, `PhysicalSize`, `PhysicalRect`, `Monitor`,
  and `Theme`, writing Tauri's JSON: `Monitor` with camelCase keys, `Theme`
  as `"light"` or `"dark"`
- `Native::Window` getters and setters behind them, in tao's names
  (`set_inner_size`, `set_outer_position`, `set_maximized`, `set_visible`,
  `drag_window`, and the rest); `Native::Window#set_size(width, height)`
  is unchanged
- The native extension depends directly on `objc2` (macOS), `gtk` (Linux),
  and `windows` (Windows), at the versions tao already locks
- `Window#is_enabled` and `Window#set_enabled`, `Window#cursor_position`,
  `Window#set_size_constraints`, `Window#set_icon` (an image that does not
  fill its size raises `Error::Runtime`, `invalid icon: ...`),
  `Window#set_background_color`, and `Window#set_shadow`
- An undecorated, resizable window can be resized by its edges on Windows
  and Linux, as in Tauri
- `AppHandle#primary_monitor`, `#monitor_from_point`, `#available_monitors`,
  and `#cursor_position` (raising `Error::Runtime`, `failed to get cursor
  position`), also on `App`; the setup hook can ask, since `App#run` builds
  the event loop before calling it
- `Webview#set_background_color`
- `Tokra::Color` (with `Color.from_str`), `Tokra::LogicalUnit`,
  `Tokra::PhysicalUnit`, and `Tokra::WindowSizeConstraints`
- `Native::Icon`, `Native::EventLoop#cursor_position`, `#primary_monitor`,
  `#monitor_from_point`, and `#available_monitors`, `Native::Window#is_enabled`,
  `#set_enabled`, `#set_inner_size_constraints`, `#set_window_icon`,
  `#set_background_color`, and `#set_shadow`, and
  `Native::WebView#set_background_color`
- Menus (`Tokra::Menu`): `Menu`, `Submenu`, `MenuItem`, `CheckMenuItem`,
  `PredefinedMenuItem`, and `IconMenuItem` with Tauri's constructors and
  methods, Submenu icons, `NativeIcon`, `MenuId`, `MenuEvent`,
  `AboutMetadata` and its builder, `MenuBuilder`, `SubmenuBuilder`,
  `MenuItemBuilder`, `CheckMenuItemBuilder`, `IconMenuItemBuilder`, and
  `Menu.default`
- Context menus: `Menu::ContextMenu#popup` and `#popup_at` on `Menu` and
  `Submenu`, `Window#popup_menu` and `#popup_menu_at`, the menu plugin's
  `popup`, and on Windows `#hpopupmenu`; other Ruby threads keep running
  while a context menu is open
- On Windows `Window#set_theme` also themes the window's menu bar
- `App` and `AppHandle#on_menu_event`, `#menu`, `#set_menu`, `#remove_menu`,
  `#hide_menu`, and `#show_menu`; `Window#on_menu_event`, `#menu`,
  `#set_menu`, `#remove_menu`, `#hide_menu`, `#show_menu`, and
  `#is_menu_visible`; `Builder#menu`, `#on_menu_event`, and
  `#enable_macos_default_menu`; `RunEvent::MenuEvent`
- On macOS an app that sets no menu gets Tauri's default menu
- The core `menu` plugin, so the menu classes of `@tauri-apps/api` work
- `Error::Menu`, `Error::BadMenuIcon`, and `Error::FailedToReceiveMessage`
- `Native::Menu`, `Native::Submenu`, `Native::MenuItem`,
  `Native::CheckMenuItem`, `Native::PredefinedMenuItem`,
  `Native::IconMenuItem`, `Native::MenuIcon`, and `Native::MenuEvent`; on
  macOS `Native.init_menu_for_nsapp` and its siblings, on Windows and Linux
  `Native::Window#init_menu` and its siblings, on Windows
  `Native::Window#set_menu_theme` and `Native::Menu#hpopupmenu`; and
  `Native::Window#popup_menu`
- Tray icons (`Tokra::Tray`): `TrayIconBuilder`, `TrayIcon` with its icon,
  tooltip, title, menu, visibility, template icon, left-click menu, temp
  directory, `rect`, and listeners, `TrayIconId`, `TrayIconEvent` (`Click`,
  `DoubleClick`, `Enter`, `Move`, `Leave`), `MouseButton`, and
  `MouseButtonState`; `Tokra::Rect`
- `App` and `AppHandle#on_tray_icon_event`, `#tray_by_id`, and
  `#remove_tray_by_id`; `Builder#on_tray_icon_event`; `RunEvent::TrayIconEvent`
- A closed or removed tray leaves the system tray at once, and every tray
  leaves it as the app exits
- `App#cleanup_before_exit` and `AppHandle#cleanup_before_exit`, for an app
  that ends its process itself
- The core `tray` plugin, so the `TrayIcon` class of `@tauri-apps/api` works
- `Error::Tray` and `Error::BadTrayIcon`
- `Native::TrayIcon`, `Native::TrayIcon::Icon`, and `Native::TrayIconEvent`;
  on Linux `Native.refuse_unbuildable_menu`
- Dependency: tray-icon 0.21.0; on Linux tray icons need an AppIndicator
  library (`libayatana-appindicator3-1`) at run time
- Dependency: muda 0.17.1, with its libxdo feature
- On Linux, libxdo is a new build (`libxdo-dev`) and run-time (`libxdo3`)
  dependency
- `Window#set_effects` with `Tokra::Effect`, `EffectState`,
  `WindowEffectsConfig`, and `EffectsBuilder`: macOS vibrancy and Windows
  Mica, Tabbed, Blur, and Acrylic
- `Window#set_progress_bar` with `Tokra::ProgressBarState` and
  `ProgressBarStatus`; `Window#set_badge_count`; on macOS
  `Window#set_badge_label`; on Windows `Window#set_overlay_icon`
- `Window#set_title_bar_style` with `Tokra::TitleBarStyle`
- `App#set_theme` and `AppHandle#set_theme`, which theme the whole app and,
  on Windows, every window's menu bar
- `Native::Window#set_effects`, `#set_progress_bar`, `#set_badge_count`,
  `#set_title_bar_style`, `#set_badge_label` (macOS), and
  `#set_overlay_icon` (Windows); `Native::EventLoop#set_theme`
- Dependency: window-vibrancy 0.6.0 on macOS and Windows
- `Tokra.generate_context(path = nil)` reads `tokra.conf.json` beside the
  entry script (or at `path`), merges `tokra.<platform>.conf.json` over
  it, and returns a `Tokra::Context`; the schema is Tauri's
- Config files may be JSON5, as with Tauri's `config-json5` feature:
  `tokra.conf.json5` and `tokra.<platform>.conf.json5` are read, a
  `tokra.conf.json` is read as JSON5 first (serde_json's error is kept when
  neither reads it), and a `.json5` json5 rejects raises
  `Utils::Config::Parse::ConfigError::FormatJson5` with json5's message;
  `Tokra.toml` still raises `DisabledFormat`
- `Tokra::Json5.from_str`, json5 0.4.1's parser, with its values and its
  pest-rendered `Tokra::Json5::Error`s
- `Tokra::Context` (`config`, `config=`, `package_info`, `package_info=`,
  `pattern`) and `Tokra::PackageInfo`
- `Builder#build(context)` and `Builder#run(context)` build the app from a
  `Tokra::Context`, and `App#package_info` and `AppHandle#package_info`
  answer its `Tokra::PackageInfo`
- `Tokra::Config` is Tauri's whole config, `Tokra::Utils::Config::Config`
- `Tokra::Utils::Config` (Tauri's config types) and its `Parse`,
  `Tokra::Codegen`, `Tokra::Pattern`, and `Tokra::Utils::Platform::Target`
- Dependency: ferro-url 0.1.0.pre.1 (url 2.5.8), for every URL Tauri types as
  `url::Url`

### Changed

- `Rack::Handler::Tokra.run` takes `context:` (or anchors at rackup's
  `config.ru`) and opens the config's windows; `title:`, `width:`,
  `height:`, and `DEFAULT_OPTIONS` are gone (breaking)
- An app opens the windows its config's `app.windows` lists, and none if it
  lists none, instead of always opening `main` (breaking)
- An app needs a config file with an `identifier` (breaking)
- A window's default title is "Tokra App", as Tauri's is "Tauri App"
- The default menu's About item, the Linux desktop file, and a dialog
  plugin message's title name the app by `package_info.name`, and the About
  item takes its version from `package_info.version` and
  `bundle.copyright` and `bundle.publisher` from the config
- As the app exits, the app's, each window's, and each webview's resources
  tables are cleared without calling `close`, and on Windows each window is
  hidden
- `Rack::Handler::Tokra.run` now builds a `Tokra::Builder`, so Rack apps get
  IPC responses and injected scripts; its `invoke_handler` receives an
  `Ipc::Invoke` and must be Ractor-shareable (breaking)
- `tokra` now requires `rb_sys ~> 0.9.129`
- `Native::WebView.new_with_protocol` takes `(window, proxy, label,
  initialization_scripts)` and builds the webview with `label` as wry's id;
  a label holding NUL raises `ArgumentError` (breaking)
- `Native::Window.new` takes `(event_loop, label)`, and every event the
  loop delivers for the window carries `label`; a label holding NUL raises
  `ArgumentError` (breaking)
- `Native::IpcEvent` gains required `label` and `url` members; `label` is
  its first positional member, before `message` (breaking)
- `Native::HttpRequestEvent`, `Native::PageLoadEvent`, and
  `Native::WindowCloseEvent` gain a required first `label` member, the
  label of their webview or window (breaking)
- `Native::HttpRequestEvent#body` is a binary (ASCII-8BIT) string holding the
  exact request bytes, no longer UTF-8 (breaking)
- `ipc://` and `postMessage` invokes from any origin other than the app's own
  (`tokra://localhost`; `http://tokra.localhost` on Windows) are rejected with
  `Command <name> not allowed by ACL` until capabilities exist (breaking)
- An invoke handler that raises rejects the invoke with the exception message
  and logs it; the native event loop reports exceptions to stderr instead of
  discarding them, and `SystemExit` ends the loop with its status
- `tokra` ships its `Cargo.lock` and compiles with `cargo --locked`, so an
  install builds the dependency versions this repository tested; magnus is
  pinned to a commit, not its main branch
- On Linux, `tokra` now requires WebKitGTK 2.40 or newer (wry's
  `linux-body` feature)
- `tokra` no longer strips its native extension's symbols, so a panic
  backtrace names its functions
- `Native::EventLoop`, `Native::Window`, and `Native::WebView` raise
  `ThreadError` when called from a thread other than the one that created
  them (breaking)
- `Native::Proxy#respond` and `#drop_response` called off the main thread
  answer through the event loop, and raise once the loop has closed
- An exception that is not a `StandardError` (a `SignalException`,
  `Interrupt`, `Thread#kill`), raised in an event callback or delivered to
  the main thread while the loop runs, ends the loop and is raised again by
  `Native::EventLoop#run`, instead of being reported and ignored (breaking)
- Events for Ruby are delivered once per turn of the event loop, after the
  platform's events, instead of one by one as they arrive
- `tokra`'s native crate now depends on the `rb-sys` crate directly, for Ruby's
  thread-event hooks
- Closing the window no longer ends the event loop by itself: the window
  closes, and the app exits unless a handler prevents it (breaking for code
  that drives `Native::EventLoop` directly, which now closes the window on
  `WindowCloseEvent` and answers `true` to `WindowDestroyedEvent`)
- A closed `Native::Window` ignores its setters and answers `nil` for its
  title and id, and a closed `Native::WebView` ignores `eval` (breaking)

### Fixed

- `rackup -s tokra` finds the handler (ships `rackup/handler/tokra`) and no
  longer raises on the options rackup passes
- Binary `tokra://` responses (images, fonts) no longer fail with an
  `EncodingError` and leave the request hanging; bodies are sent byte-exact
- Binary request bodies reach Rack intact instead of being UTF-8 mangled
- Output written to a pipe or file is no longer lost when the app exits, and
  `at_exit` hooks and `ensure` clauses run: `Native::EventLoop#run` ends the
  process by raising `SystemExit` with the loop's exit code instead of letting
  tao call `process::exit`
- Native extensions failing to load on macOS 27 ("load command #4 string
  extends beyond end of load command"): rb_sys 0.9.129 gives the bundle a
  valid install name instead of an empty one
- Request bodies sent over `tokra://` and `ipc://` arriving empty on Linux:
  wry's `linux-body` feature is now on, as in Tauri
- Background Ruby threads stopping while the window is idle and while a
  Windows menu tracks: the event loop now hands them the GVL once per turn
  whenever they wait for it, and from inside a menu's modal loop, so a
  CPU-bound thread can neither starve them nor freeze the window and its
  exit
- `SIGTERM`, `SIGHUP`, and `SIGQUIT` with Ruby's default handlers being
  printed and ignored by a running app; they now end it as they end any
  Ruby program, within about 100 ms even while the window is idle, and an
  app's own `trap` handlers for those signals run as promptly
- A webview call from a background thread reaching wry off the main thread,
  and a window or webview freed by a garbage collection on another thread
  being destroyed there; the webview case was undefined behavior, and the
  window case deadlocked on macOS
- A response sent from a background thread deadlocking the app on macOS
- On Linux, webviews are built into their window's GTK box, as Tauri builds
  them, instead of through wry's X11-only path, which adopted the window's
  own X window and closed the window, ending the app, when the webview
  dropped; webviews now work under Wayland too
- `tokra` failing to load on Windows (`The specified module could not be
  found`): the build installs `WebView2Loader.dll`, which the extension
  imports, beside it, and `require "tokra"` adds that directory to Windows'
  DLL search path

### Removed

- `Native::WebView.new(window, url, ipc_callback, proxy)`; build a webview
  with `Native::WebView.new_with_protocol` (breaking)
- The `tokra` gem no longer ships development files (plans, transcripts,
  tasks, tests, tool configuration) or the empty `semantic-highlight`
  executable

[Unreleased]: https://github.com/setdef/Tokra/compare/v0.0.1.pre.2...HEAD