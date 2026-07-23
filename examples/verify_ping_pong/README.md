<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Tokra Ping-Pong Verification App

A minimal Roda application that drives Tokra's IPC round trip end to end
through the real `@tauri-apps/api`, served over the `tokra://` custom protocol.

## Purpose

This example verifies that:

1. A Rack app (Roda) runs inside Tokra via `Rack::Handler::Tokra`
2. `with_global_tauri` injects `@tauri-apps/api` as `window.__TAURI__`
3. `window.__TAURI__.core.invoke('ping', …)` resolves over the `ipc://`
   custom-protocol transport (Tauri's desktop default)
4. Form submissions, redirects, and a JSON `fetch` all work over `tokra://`

## Running

```bash
cd examples/verify_ping_pong
bundle exec ruby app.rb "your message here"
```

Click **Send via IPC**. The rendered reply (`PONG: your message here`) confirms
the invoke round trip. Because `with_global_tauri` is on and Tokra now serves
`ipc://`, the real client rides the custom protocol — so the developer console
shows **no** "IPC custom protocol failed, Tauri will now use the postMessage
interface instead" warning. That absence is the proof the transport is live;
if it appears, the client fell back to `postMessage`.

## Architecture

See [ADR 010](../../doc/contributors/adr/010.md) for the `ipc://` transport and
[ADR 002](../../doc/contributors/adr/002.md) for the Rack integration.
