<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Lessons from earlier ports

Each entry names the mistake, where it was found, and the habit that
prevents it. The plans and ADRs cited hold the full story.

## Reading the source

- **An earlier plan is not the source.** Plan 009 told Phase 2.3 to return
  `nil` from an empty clipboard; `desktop.rs` propagates the error. Plan 012
  audited the existing layer against the source first and overturned it.
- **Read the signature, not just the body.** tao's `EventLoop::run` returns
  `!` and calls `process::exit`, so code placed after it never ran outside
  tests. Tauri emits `RunEvent::Exit` from `Event::LoopDestroyed`
  (Plan 016, item 5).
- **Follow the input through every layer.** wry rewrites the WebView2
  workaround URI before Tokra sees it, so an `http://ipc.localhost/` branch
  was dead code (Plan 016, item 16).
- **Pin behavior to the locked version.** serde_json's handling of `NaN`
  came from the version Tauri's `Cargo.lock` pins (Plan 016 review).

## Testing

- **A stub can hide a missing method.** The clipboard plugin called
  `app.manage`, which only a test double implemented; `AppHandle` inherited
  a `NotImplementedError` default, and its RBS declaration hid that from
  Steep (Plan 016, item 4). Test on a real handle, and let `rbs:parity`
  catch declarations an ancestor only stubs.
- **Code only tests can reach is not done.** IPC responses placed in `App`
  were unreachable because real apps ran a second Rack event loop; the fix
  unified the paths (Plan 014 amendment, ADR 009).
- **The real client is the proof of a wire format.** A hand-written test
  encodes your reading of the format on both ends. Plan 015 drove `ipc://`
  with the vendored `@tauri-apps/api`.
- **A fix is not a fix until you can say why it worked.** Chat 004 credited
  `File.read` for a stylesheet fix that other edits in the same session made;
  for binary assets `File.read` is wrong (Plan 016, item 2).
- **Name what you could not test.** Native paths inside tao's loop are listed
  as untested without a display, with the manual check for each (Plan 016).

## Failure paths

- **Every request settles.** Swallowed exceptions in the native loop and an
  unrescued handler left invokes pending forever (Plan 016, item 3).
- **Rust panics end the VM.** An empty image reached arboard and panicked;
  the guard raises arboard's own `ConversionFailure` message (Plan 016,
  item 6; Plan 012, decision 5).
- **Validate arguments in Tauri's words.** Missing keys and out-of-range
  numbers raised `TypeError` outside the rescue list (Plan 016, item 7).
- **Do not rescue `LoadError` around a native require** (Plan 016, item 8).

## Packaging

- **The working tree hides packaging bugs.** The gem shipped without its
  vendored scripts, and its crate inherited lints from a workspace the gem
  did not contain (Plan 016, item 1). `package:check` now builds and loads
  each gem from its package (Plan 017).

## Documentation

- **Undocumented deviations count as bugs.** Plan 016, item 17 moved four of
  them into ADR 009 and ADR 010.
- **Stopgaps need the maintainer and an ADR.** The local-origin check is
  stricter than Tauri until capabilities exist (Plan 016, item 10; ADR 010).
