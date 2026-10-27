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
- `Invoke#webview` accessor returns calling webview (now required parameter)
- `AppHandle#windows` returns all managed windows
- `AppHandle#get_window(label)` fetches window by label
- `AppHandle#get_webview(label)` fetches webview by label
- `AppHandle#resources_table` returns app-level fallback table
- `Manager#resources_table` abstract method for unified interface
- `App`, `Window`, and `Webview` are full `Manager`s, as in Tauri: `manage`,
  `state`, `try_state`, `config`, and the window and webview lookups reach the
  app from whichever handle you hold
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
- `Tokra::Image.from_path` decodes a PNG or ICO file to raw RGBA, raising
  `Tokra::Error::Io` (Tauri's `Error::Io`) when the file cannot be read,
  with Rust's message for a path holding a NUL byte
- `Tokra::Error::Image` raised when image bytes cannot be decoded
- `Tokra::JsImage.deserialize` reads a frontend image payload (file path,
  byte array, resource ID, or RGBA hash) as Tauri does, raising
  `CommandItem::Mismatch` for any other value, and `JsImage#into_img`
  resolves it into a `Tokra::Image`
- Registered plugins receive `RunEvent::Ready`, `RunEvent::WindowEvent`
  (close requested), and `RunEvent::Exit` through `Plugin#on_event`, before
  the run callback; `Exit` is emitted from the native loop's
  `Native::LoopDestroyedEvent`, since tao's event loop never returns
- Frontend `invoke` promises now resolve and reject: `App` evaluates Tauri's
  `runCallback` in the WebView, so `@tauri-apps/api` works end to end
- `Tokra::Ipc::FormatCallback` formats invoke responses as callback scripts
- Injected `__TAURI_INTERNALS__` initialization scripts (vendored from Tauri
  via `rake sync:tauri`), guarded by a per-app invoke key
- `Tokra.generate_invoke_key` returns a Z85-encoded random invoke key
- `Builder#app(rack_app)` serves a Rack application over the `tokra://` protocol
- `Builder#title` and `Builder#size` configure the window
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
  `postMessage`), other text is sent as JSON text in UTF-8
- `Tokra::Ipc::InvokeBody.raw?` tells raw bytes from JSON
- A `postMessage` whose `options.headers` the http crate refuses is
  reported with `console.error("JSON error: ...")` and not dispatched
- `Builder#with_global_tauri` injects the vendored `@tauri-apps/api` bundle as
  `window.__TAURI__`, so a page with no frontend bundler calls
  `window.__TAURI__.core.invoke(...)` directly (mirrors Tauri's
  `app.withGlobalTauri`); also available as
  `Rack::Handler::Tokra.run(app, with_global_tauri: true)`
- `Plugin#initialization_script` is injected into every page after Tauri's
  init scripts, wrapped in an IIFE; `PluginStore#initialization_script`
  collects them
- `AppHandle#manage(state)` stores managed state and returns whether it did
- `Native::Proxy#drop_response(request_id)` closes a pending protocol request
  without a reply
- `Native::LoopDestroyedEvent`, delivered as the native event loop ends
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
  to the calling window as Tauri does, on Windows and X11 only (ferro-rfd
  binds no macOS or Wayland handle); picked paths join no scope; it is pure
  Ruby and depends on `ferro-rfd` 0.1.0.pre.2 (rfd 0.17.2), which apps
  take from its git tag until it is on RubyGems.org
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
  depends on `ferro-notify-rust` 0.1.0.pre.3 (notify-rust 4.18.2),
  `ferro-url` 0.1.0.pre.1 (url 2.5.8), and `ferro-time` 0.1.0.pre.1 (time
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
  `Channel.from_command(invoke, key)` and `send` it JSON values
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
  `WaylandWindowHandle`, and their display handles), read on the main
  thread, raising `RawWindowHandle::HandleError::Unavailable` from another
  thread once the event loop has ended; on X11 every display handle is the first one tao opened
- `Native::Window#raw_window_handle` and `Native::Window#raw_display_handle`
- `App#set_activation_policy` and `Tokra::ActivationPolicy` (`Regular`,
  `Accessory`, `Prohibited`), on macOS only, as in Tauri: set before the
  event loop runs, such as in the setup hook; a `Prohibited` app never
  becomes the active app or takes the keyboard
- `Native::EventLoop#set_activation_policy`, on macOS only
- `Window#set_always_on_top` and `Window#set_ignore_cursor_events`, with
  `Native::Window#set_always_on_top` and `Native::Window#set_ignore_cursor_events`

### Changed

- `Plugin#on_event` now receives the app handle: `on_event(app, event)` (breaking)
- `Plugin#on_window_created` renamed to `Plugin#window_created` (breaking)
- `Plugin#on_webview_created` renamed to `Plugin#webview_created` (breaking)
- `Tokra::Invoke` is now `Tokra::Ipc::Invoke` (breaking)
- `Invoke#payload` is now the message's `payload` member, not the whole IPC
  message (breaking)
- `Rack::Handler::Tokra.run` now builds a `Tokra::Builder`, so Rack apps get
  IPC responses and injected scripts; its `invoke_handler` receives an
  `Ipc::Invoke` and must be Ractor-shareable (breaking)
- `tokra` now requires `rb_sys ~> 0.9.129`
- `Native::WebView.new_with_protocol` takes `(window, proxy,
  initialization_scripts)` (breaking)
- `Native::IpcEvent` gains a required `url` member (breaking)
- `Native::HttpRequestEvent#body` is a binary (ASCII-8BIT) string holding the
  exact request bytes, no longer UTF-8 (breaking)
- `Ipc::Invoke` responders receive the response serialized as JSON text, and a
  value JSON cannot encode rejects the invoke with the serializer's message
  (breaking for code that builds an `Invoke` with its own responder)
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
- `Window#set_title`, `Window#set_size`, `Webview#eval`, and
  `AppHandle#emit` called from another thread run on the main thread and
  return `nil` without waiting, as in Tauri
- `Webview#eval` logs a script the webview fails to evaluate instead of
  raising
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

### Fixed

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
- Background Ruby threads stopping while the window is idle: the event loop
  now hands them the GVL once per turn whenever they wait for it, so a
  CPU-bound thread can neither starve them nor freeze the window and its
  exit
- `SIGTERM`, `SIGHUP`, and `SIGQUIT` with Ruby's default handlers being
  printed and ignored by a running app; they now end it as they end any
  Ruby program
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

- The `tokra` gem no longer ships development files (plans, transcripts,
  tasks, tests, tool configuration) or the empty `semantic-highlight`
  executable

[Unreleased]: https://github.com/setdef/Tokra/compare/v0.0.1.pre.2...HEAD