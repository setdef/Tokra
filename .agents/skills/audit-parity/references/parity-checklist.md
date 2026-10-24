<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Parity checklist

Check each row against the cited source and write the citation into the
plan's fidelity table.

## Names and shape

- Class, module, method, hook, and command names match Tauri's
  (`window_created`, not `on_window_created`). Do not invent a hook Tauri
  lacks; map Tauri's lifecycle onto Ruby's (`Plugin::initialize` is the Ruby
  constructor, called at registration).
- Wire names stay as the frontend sends them (`altText`, not `alt_text`).
- Command routing parses exactly as Tauri does (`plugin:a|b|c` routes
  command `b`, the second `|` token).
- Rust machinery is translated, not ported: lifetimes, `Arc<Mutex<_>>`,
  `Send`, and Cargo features have no Ruby API. A feature Tauri gates behind
  a Cargo feature is simply on.

## Messages

- Error and rejection text is copied verbatim from the Rust source,
  including serde's wording: `invalid args `{key}` for command `{cmd}`: {msg}`,
  `command {cmd} missing required key {key}`, `invalid type: ..., expected ...`,
  `data did not match any variant of untagged enum ...`.
- Library errors keep the library's Display text (arboard's messages pass
  straight through `Error::Clipboard(String)`).
- Log lines Tauri prints (for example the invoke-key mismatch) match too.

## Values and encodings

- Byte lengths, not character counts, where Rust uses `len()`.
- Integer grammars and ranges match the Rust type (`u32::from_str` takes an
  optional `+` and ASCII digits, nothing else; `u8` arrays reject 256 and
  1.5 instead of wrapping or truncating).
- Binary data crosses the boundary as bytes (`RString#to_bytes`,
  `File.binread`), never through a UTF-8 `String`.
- Serialization follows the serde_json version Tauri locks (non-finite
  floats become `null`).
- Header and MIME comparisons include parameters when Tauri's do.

## Ordering and lifecycle

- Script injection order, plugin hook order, and event order match Tauri's
  (cite the `manager/webview.rs` or `app.rs` lines).
- Work Tauri does after a call that returns `!` (never returns) happens
  where Tauri really does it, usually in the runtime's event handler.
- State a plugin manages is the state it reads and cleans up, not a private
  copy.

## Failure

- Every invoke settles: handler exceptions and unserializable values become
  rejections, as Tauri's `InvokeResponse` conversions do.
- No input reachable from the frontend panics native code; a Rust panic
  ends the Ruby VM. Guard it and raise Tauri's error message instead.
- A `LoadError` from a native extension surfaces with its real message.
- Branches that cannot run (because a dependency rewrites the input first)
  are removed, with the dependency line cited.

## Security

- Origin and ACL decisions follow Tauri's `is_local_url` and capability
  checks; any stopgap stricter or looser than Tauri is maintainer-approved
  and recorded in an ADR.

## Documentation

- Every deviation is listed in the plan and in the ADR or RDoc a user reads,
  with the precedence tier that justifies it.
- Behavioral caveats from Tauri's rustdoc (for example the Linux main-thread
  clipboard deadlock) are ported, not dropped.
