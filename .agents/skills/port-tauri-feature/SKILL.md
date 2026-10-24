---
name: port-tauri-feature
description: Ports a Tauri feature (a core API, IPC behavior, or an official plugin) to Tokra's Ruby backend and thin Rust bindings. Covers finding and citing the authoritative source, writing the plan, test-first work with real collaborators, the parity checklist, SPDX attribution, documenting deviations, and the definition of done. Use when adding or changing behavior that mirrors Tauri, wry, tao, or a tauri-apps plugin.
---

<!-- SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com> -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Port a Tauri feature

AGENTS.md is the contract: design precedence, RBS and RDoc rules, commands,
changelog, and the definition of done. This skill is the workflow around it.
Read AGENTS.md first, then `doc/contributors/documentation_style.md` before
writing prose.

## 1. Find the authority, never guess

| Source | Where |
|---|---|
| Tauri core | `vendor/tauri` (pinned submodule; `git submodule update --init` if empty) |
| wry, tao, arboard, magnus, rb-sys, serde_json | The locked copy: `cargo metadata --format-version 1` and read each package's `manifest_path` directory. Run it in the workspace that uses the crate (root, or `plugins/<name>`). |
| Official plugins | `https://github.com/tauri-apps/plugins-workspace` at the version being ported. Clone or fetch it into an ignored scratch directory (for example under `tmp/`), never into a tracked path. |
| Behavior that depends on a dependency version | The version Tauri's own `Cargo.lock` pins, not the newest release. |

Record the commit or version you read. Cite `file:line` ranges for every
behavior you port. A claim you could not check is marked UNVERIFIED, not
stated as fact.

## 2. Plan before code

Read the relevant ADRs in `doc/contributors/adr/` and the latest plans in
`doc/contributors/plan/`. Write the next numbered plan with the SPDX header
the other plans use. A plan has: context, a fidelity audit table (behavior,
Tauri with citation, Tokra today, verdict), numbered design decisions, the
changes, verification, out of scope, and risks. Audit what already exists
before adding to it: earlier plans have baked in deviations that a later
reading of the source overturned.

A decision that breaks a Tauri behavior names the AGENTS.md precedence tier
that justifies it (Ruby the language over fidelity, never "Ruby culture" over
fidelity) and lands in the ADR or RDoc where a reader will meet it.

## 3. Test first, against real collaborators

- Write the test, run it, and watch it fail for the reason you expect.
- Drive the real object graph: `Tokra::Builder.default.build(native: StubNative)`
  gives a real `App` and `AppHandle`; stub only the native window and event
  loop. A test double that answers a method the real class lacks hides the
  gap (that is how `AppHandle#manage` went missing).
- For a wire format, let the real client be the proof: the vendored
  `@tauri-apps/api` and Tauri's own scripts, not a hand-written imitation.
- For each new behavior, name the test that fails if the line is deleted or
  a key constant or branch changes. Spot-check by reverting the line,
  running the test, and restoring it.
- Native paths that need a display or never return (tao's loop) get an
  explicit "untested without a display" list in the plan, with what a
  manual run confirms.

## 4. Port to the parity checklist

Work through [references/parity-checklist.md](references/parity-checklist.md):
names, error messages verbatim, wire formats, ordering, edge cases, and what
happens on failure. Every request settles; nothing panics the VM.

## 5. Attribute

Wrap code or prose derived from Tauri or a plugin in an SPDX snippet
(`Apache-2.0 OR MIT`, the upstream copyright line) and cite the file. Ruby
files use `#--`/`#++` around the header; see existing ports such as
`plugins/clipboard/lib/tokra/plugins/clipboard.rb` for the snippet form.

## 6. Finish

- Signatures in `sig/` (or `plugins/<name>/sig/`) for every public method;
  the `rbs:parity` gate checks both directions.
- RDoc in Context-Problem-Solution form with a Tauri citation; no endless
  `def x = y` (RuboCop rejects them in RDoc'd paths).
- A CHANGELOG line for anything an app developer can observe.
- A packaged file the gem loads at run time is in `spec.files`; the
  `package:check` gate proves it.
- Run the clean-build gate from AGENTS.md. Then walk the plan item by item
  and mark each done or deferred with a reason; nothing is silently
  skipped.
- Hand off with the commit-session skill.

The project's past mistakes, with the fix each taught, are in
[references/lessons.md](references/lessons.md). Skim it before designing.
