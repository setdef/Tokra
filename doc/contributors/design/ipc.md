<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# The IPC Path

This document says how a page's `invoke` reaches Ruby and how its answer
gets back: the two transports, how a command is routed, how each
transport answers and fails, which origins may invoke, how the page gets
`@tauri-apps/api`, and where Tokra departs from Tauri. It is for Tokra's
contributors. Why the page speaks Tauri's protocol is ADR 008. The
dispatch in `lib/tokra/app.rb` carries the Tauri source lines for each
step.

Tauri citations are to `vendor/tauri` at `9f0306fbc`, under
`crates/tauri/src/` unless they name another crate.

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
not found`. Each transport supplies only what differs: how it reads the
raw invoke key (a JSON member for `postMessage`, the `Tauri-Invoke-Key`
header for `ipc://`), how it parses the payload, where it finds the
origin, its responder, and its drop action.

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

`test/integration/ipc_transport_test.rb` drives the real
`@tauri-apps/api`, loaded through `withGlobalTauri`, over `ipc://` in a
real webview, and never falls back to `postMessage`.
`test/integration/origin_acl_test.rb` checks the stopgap against a
foreign frame. The core tests under `test/builder/` cover both
responders and both failure modes.
