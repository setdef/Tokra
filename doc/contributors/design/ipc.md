<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# The IPC Path

This document says how a page's `invoke` reaches Ruby and how its answer
gets back: the scripts the page runs, the two transports, how a command
is routed, how each transport answers and fails, the invoke key, which
origins may invoke, how the page gets `@tauri-apps/api`, where commands
run, and where Tokra departs from Tauri. It is for Tokra's
contributors. Why the page speaks Tauri's protocol is ADR 008. The
dispatch in `lib/tokra/app.rb` carries the Tauri source lines for each
step.

Tauri citations are to `vendor/tauri` at `9f0306fbc`, under
`crates/tauri/src/` unless they name another crate.

## The page's scripts

The `__TAURI_INTERNALS__` object the page needs is built by
initialization scripts, and Tokra writes none of them. `rake sync:tauri`
vendors Tauri's own scripts from the pinned submodule (`init.js`,
`pattern.js`, `ipc.js`, `ipc-protocol.js`, `core.js`,
`process-ipc-message-fn.js`, and the event scripts) into
`lib/tokra/js/`, turning Tauri's serialize-to-javascript markers into
ERB, and aborts if its extraction patterns stop matching. `App` assembles
them in Tauri's injection order (`manager/webview.rs`), so the injected
side is Tauri's code verbatim. Regenerating them is a manual step.

The frontend's `invoke` sends one message, `{cmd, callback, error,
payload, options, __TAURI_INVOKE_KEY__}` (`ipc/protocol.rs`), where
`callback` and `error` are integer callback ids.

## Two transports

`ipc://` is the primary transport, as it is Tauri's desktop default, and
`postMessage` is the fallback. Tokra registers two asynchronous custom
protocols, `tokra` and `ipc`. Both forward the same
`UserEvent::HttpRequest`, storing wry's responder by `request_id`, so the
native binding adds one registration, no new event variant, and no new
response API. `App` routes a forwarded request on the scheme its
protocol was registered under, which the native layer puts on the
request, not on its URI: a scheme the app registered goes to its
handler, `ipc` and `tokra` included, as a held `tauri` or `ipc` does in
Tauri (`manager/webview.rs:222-280`); otherwise `ipc` goes to the
`ipc://` transport, and `tokra` to the content path. On Windows the page
fetches `http://ipc.localhost/…`, but wry's WebView2 backend reverts
that to `ipc://localhost/…` before calling the handler
(`webview2/mod.rs` `prepare_request`), so Ruby sees `ipc` on every
platform.

The vendored `ipc-protocol.js` selects `postMessage` on its own when a
`fetch('ipc://…')` rejects, so hand-rolled `window.ipc.postMessage`
callers keep working. Once `ipc://` answers, the client stays on it.

## One routing shape

Tauri routes both transports through `webview.on_message`. Tokra
routes both through one private `App#route_invoke`: `plugin:`-prefixed
commands go to the plugin store and everything else to the app's
`invoke_handler`, and an unclaimed command rejects with `Command NAME
not found`. The app's `invoke_handler` is a block that dispatches on
`invoke.command` at run time, where Tauri's is a dispatch table its
`generate_handler!` macro builds when the app compiles. Each transport supplies only what differs: how it reads the
raw invoke key (a JSON member for `postMessage`, the `Tauri-Invoke-Key`
header for `ipc://`), how it parses the payload, where it finds the
origin, its responder, and its drop action.

## The postMessage responder

A `postMessage` invoke is answered by evaluating
`window.__TAURI_INTERNALS__.runCallback(id, value)` in the calling
webview: the callback id on success, the error id on failure. The
JavaScript comes from `Tokra::Ipc::FormatCallback`, a port of Tauri's
`ipc/format_callback.rs`, including its 10 KiB `JSON.parse('...')`
heuristic. A raw body evaluates as a JSON number array, as Tauri's
`format_result` writes it on macOS and whenever the client reports
`customProtocolIpcBlocked`. Off macOS, a successful object, array, or
raw result travels over `Channel.from_callback_fn` instead, as Tauri
sends it, unless the command is the channel-data fetch or the message
reports `customProtocolIpcBlocked` (`ipc/protocol.rs:337-407`). The
message's `options.headers` become the command's headers, checked as
the http crate checks them.

## The ipc:// responder

The client reads the HTTP response and calls `runCallback` itself
(`ipc-protocol.js`), so the `ipc://` responder replies over HTTP rather
than evaluating `runCallback`; the `postMessage` path keeps
`Ipc::FormatCallback`. A resolved and a rejected invoke both reply
`200`, told apart by the `Tauri-Response` header (`ok` or `error`), as
in `ipc/protocol.rs`. A JSON value or an error answers as
`application/json`, and a raw body as `application/octet-stream`. Every
reply carries `Access-Control-Allow-Origin: *` and
`Access-Control-Expose-Headers: Tauri-Response`, matching Tauri's shared
`respond` closure, so the cross-origin client can read the header. An
`application/octet-stream` request body reaches the command as a binary
String, and its headers with it (`ipc/protocol.rs:106-135`, `525-548`).

## Two failure modes

A malformed `ipc://` request, with a missing or non-u32
`Tauri-Callback` or `Tauri-Error`, a missing `Tauri-Invoke-Key`, a
missing `Origin` or one that is not a URL, unparseable JSON, or an
unknown or unimplemented content type (parameters count, as in Tauri's
`Mime` comparison), replies 500 `text/plain` with the parse message
(`ipc/protocol.rs`), which the client surfaces as a rejection.

A key mismatch on an otherwise well-formed request logs Tauri's exact
message and drops with no reply (`webview/mod.rs`). Tauri drops by
letting its owned responder fall out of scope; Tokra's responder lives
in a map keyed by `request_id`, so `Proxy#drop_response(request_id)`
removes and drops it. wry's responder has no `Drop`, so nothing answers
the request, the client's `fetch` stays pending, and the invoke never
settles, as in Tauri.

## The invoke key

`Tokra.generate_invoke_key` mirrors Tauri's `generate_invoke_key`: 16
random bytes, Z85-encoded by `Tokra::Z85`. `AppManager` holds the key,
the scripts carry it, and every message is checked against it. A
mismatch is logged to stderr and the message is dropped without an
answer, as Tauri's `Webview::on_message` does (`webview/mod.rs`).

## Only the app's own origin may invoke

Tauri decides whether an invoke is local with `is_local_url`
(`webview/mod.rs:1680-1722`): the origin's scheme and domain match the
app's protocol URL, or the page comes from a scheme the app registered.
Remote origins then get only what capabilities grant. Tokra has no
capabilities yet, and wry injects the initialization scripts, invoke key
included, into every top-level document, so without a check any page
the webview loads could call every command.

As a stopgap, `App#route_invoke` rejects an invoke whose origin is not
local, before dispatch, with Tauri's release-build ACL message `Command
<cmd> not allowed by ACL`. Local means the scheme and host of
`tokra://localhost` on macOS and Linux and `http://tokra.localhost` on
Windows, where wry serves custom protocols over http, or a page from a
scheme the app registered. The `ipc://` transport reads the `Origin`
header, which must parse as a URL (`Origin header is not a valid URL`,
`ipc/protocol.rs:491-499`). For `postMessage`, wry passes the posting
frame's URL as the request URI, and Tauri parses it into
`InvokeRequest.url` (`ipc/protocol.rs:302`), so the native layer
forwards it as `Native::IpcEvent#url` and the same check applies. The
channel-data fetch command, `plugin:__TAURI_CHANNEL__|fetch`, is exempt,
as Tauri exempts it from the ACL (`webview/mod.rs:1802-1806`). Data ids
are sequential and process-wide, so any frame that reaches the IPC can
fetch queued data that is not its own, as in Tauri.

On Linux the `postMessage` URI is not the posting frame's: wry's
WebKitGTK backend reports the webview's top-level URI for every message
(wry 0.54.1 `src/webkitgtk/mod.rs:635-645`), so a foreign frame's message
carries `tokra://localhost` and passes the check over `postMessage`.
Tauri has the same gap: it parses that URI and decides locality from it
(`webview/mod.rs:1726`). The `ipc://` transport is unaffected, since
WebKitGTK sends the frame's own `Origin` header.

This is stricter than Tauri for remote pages, which Tauri lets call app
commands when the app has no app manifest (`webview/mod.rs:1802`), and
looser for the app's own pages, which Tauri refuses any plugin command
no capability grants. The stopgap goes when the access-control port's
check turns on ([config.md](config.md), "Access control").

## withGlobalTauri

A page with no frontend bundler runs `@tauri-apps/api` through Tauri's
`withGlobalTauri`, which injects the API's prebuilt IIFE
(`bundle.global.js`) as an initialization script, exposing the whole API
as `window.__TAURI__`. When the config's `app.withGlobalTauri` is set,
`WebviewManager` appends the vendored `bundle.global.js` after the core
init scripts, mirroring `manager/webview.rs`; Tauri's codegen reads the
same key when it compiles. `rake sync:tauri` vendors `bundle.global.js`
from the pinned submodule, built by the API package's own rollup, so
Tokra never hand-bundles Tauri's JavaScript.

## One App path

`App` owns the event loop, the windows, the webviews, script injection,
and IPC dispatch, as Tauri's `App` does. `Builder#app(rack_app)` serves a
Rack app over `tokra://` by handing it to a `Rack::Handler::Tokra`
instance, whose one job is translating each request and response. `App`
never learns what Rack is: it holds a protocol adapter, as Tauri's
manager holds the asset protocol handler. `Rack::Handler::Tokra.run`
builds a `Builder` and runs it, so there is no second event loop, and a
Rack- or Rails-served page gets the same scripts and working `invoke`
answers as any other. The handler keeps its Rack name and `.run` entry,
so `rackup -s tokra` works.

A Rack or Rails app runs inside the Tokra process, called in memory,
rather than behind a TCP server in a child process with the webview
pointed at `http://localhost`: no port opens that other processes can
reach, no loopback stands between the page and the app, and no server
process outlives the window. This was decided on 2026-01-29. The
handler maps each `tokra://` request to a Rack env, calls the app, and
answers with the body joined whole, so a streamed response, such as
`ActionController::Live`, arrives only when it ends; a page that needs a
stream uses events over the IPC instead. WKWebView follows no redirect
from a custom protocol, so the handler follows a 3xx itself, up to a
limit, carrying `Set-Cookie` across it, and the webview keeps the
cookies for the protocol as for any origin.

## Where commands run

`App` dispatches every command synchronously on the main Ractor, and the
responder answers directly. The responder is an opaque callable on
`Ipc::Invoke`, so a later move of the app's logic to a worker Ractor
(ADR 001) can replace it without touching handlers. Until then the
responder captures its webview and must never cross a Ractor boundary,
and the Rack app also runs on the main Ractor.

## Deviations from Tauri

- **A `postMessage` invoke is read as a whole JSON value.** Tauri
  deserializes it into its `Message` struct; Tokra parses it with
  serde_json's grammar (`Ipc::Json`) and reads its members. serde skips
  the struct's unknown fields with `ignore_value`, which checks neither
  surrogates nor number ranges (serde_json `de.rs:1100-1281`), so Tokra
  rejects a lone surrogate there that Tauri accepts. A message Tauri
  cannot read, and a `cmd` that is present but not a string, are
  reported as Tauri reports them, with `console.error("JSON error: ...")`
  evaluated in the webview; the bad `cmd`'s report lacks the line and
  column serde gives it.
- **A loose `postMessage` is tolerated.** A message that is not an
  object is logged to stderr, a missing `cmd` is the empty command, and a
  message without integer callback ids is fire-and-forget, so hand-rolled
  `window.ipc.postMessage` calls keep working. Options that are not an
  object, and a `customProtocolIpcBlocked` that is not a bool, are
  ignored, where serde fails the message (`ipc/protocol.rs:223-241`).
- **Failures always settle.** A handler exception rejects the invoke
  with its message, and so does a value whose serialization raises,
  mirroring Tauri's `InvokeResponse` conversion (`ipc/mod.rs:240-276`).
  Non-finite floats are not failures: like serde_json (`ser.rs:157-174`),
  Tokra writes them as `null`. The only rejection with no Tauri
  counterpart is a String holding invalid UTF-8, which a Rust `String`
  cannot hold in the first place.

## Tests

A change is proven by a full round trip through a real window, webview,
and IPC layer, not by stubs alone: the real-window tests in
`test/integration/`, one per concern, each driving a small fixture app,
run on Linux, macOS, and Windows in CI (plan 018).

`test/integration/ipc_transport_test.rb` drives the real
`@tauri-apps/api`, loaded through `withGlobalTauri`, over `ipc://` in a
real webview, and never falls back to `postMessage`.
`test/integration/origin_acl_test.rb` checks the stopgap against a
foreign frame. The core tests under `test/builder/` cover both
responders and both failure modes.
