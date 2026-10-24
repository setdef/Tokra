<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# AGENTS.md

## Project

Tokra is a 1:1 port of Tauri to Ruby (>= 4.0.1): desktop apps with a Ruby backend and a web frontend. Rust (rb_sys + magnus, in `ext/`) is a thin binding over tao and wry; Ruby owns all logic (ADR 001, 005). First-party plugins live in `plugins/`. Standalone crate bindings are moving to Ferro, a separate project of 1:1 crate-binding gems.

Pre-1.0, zero external users. Prefer good design over backward compatibility; record every breaking change in CHANGELOG.md.

## Design precedence

1. **Ruby the language.** What Ruby can and cannot express. Rust constructs with no Ruby meaning (lifetimes, ownership, Cargo feature flags) are translated, not ported. A feature Tauri gates behind a Cargo feature is simply supported.
2. **Tauri fidelity.** Names, class structure, error messages, wire formats, and behavior MUST match Tauri's Rust source. Do not invent "more Ruby-like" APIs.
3. **Ruby culture.** Idioms yield to 1 and 2.

The authority is the pinned submodule `vendor/tauri` (`git submodule update --init` if empty). For Rust dependencies (wry, tao, arboard, magnus, rb-sys), read the exact locked source Cargo already downloaded; `cargo metadata --format-version 1` gives each package's `manifest_path`. For anything else, such as Tauri's official plugins, use the upstream repository (https://github.com/tauri-apps/plugins-workspace) at the version being ported, and fetch it into an ignored scratch directory if you need it locally. Never guess at a reference's contents. Cite the file and lines you ported, and add an SPDX snippet (Apache-2.0 OR MIT) around any code or prose derived from it.

## How to work

- Research before designing: read the Tauri source and the relevant ADR in `doc/contributors/adr/` first.
- Root-cause every fix. If you cannot explain why a change fixed the symptom, it is not a fix.
- Write tests first. A test must fail if the code it covers is deleted or mutated, and must exercise real collaborators, not stubs that hide missing behavior.
- Design in the spirit of Kent Beck (small steps, Implementation Patterns), Freeman & Pryce (tests drive interfaces), Sandi Metz (duplication over the wrong abstraction), Rebecca Wirfs-Brock (responsibility-driven roles), Martin Fowler (refactor in behavior-preserving steps), and Matz (programmer happiness). Write prose in the style of `doc/contributors/documentation_style.md`.
- Skills in `.agents/skills/` hold the detailed workflows: `port-tauri-feature` before porting, `audit-parity` before approving a diff, `commit-session` to finish a session. Mutation testing is not automated yet, so reviewers check by hand that each changed behavior has a test that fails when its code is reverted.

## Ruby, RBS, and docs

- `Data.define` for value objects (`class Foo < Data.define(...)`), `class` for entities.
- Every Ruby method has an RBS signature in `sig/` mirroring `lib/`. No `untyped`, no comments in `.rbs`. For `Data.define` classes, declare `self.new` instead of `initialize` (Steep mis-checks `initialize` there); plain classes declare `initialize` as usual.
- RDoc (never YARD) in `.rb` files only. Wrap SPDX headers in `#--` / `#++`.
- Architectural decisions get an ADR; plans live in `doc/contributors/plan/`.
- `examples/` is documentation for app developers: small, focused, and copyable. Never put test hooks, probes, or fixtures there; those live under `test/`.

## Commands

- Run Ruby with `bundle exec ruby`. Run tests with `bundle exec rake test`. Never `ruby -Ilib:test`.
- `bundle exec rake` is the gate: tests, RuboCop, Steep, RBS parity, RDoc coverage, REUSE, Clippy, fmt, and a packaging check that loads each built gem outside the repository. It must pass with zero errors and zero warnings. Run `bundle exec rake rubocop:autocorrect` first to save time.
- Approved exceptions live in `rbs_exceptions.rb` and `clippy_exceptions.rb`; adding one needs a justification that it is impossible otherwise.
- Each native gem is its own Cargo workspace with a committed `Cargo.lock`, built with `--locked`. After changing a gemspec, `Cargo.toml`, or `extconf.rb`, and before any release, also run `bundle exec rake package:install`, which compiles every gem from its packaged sources.
- Rake tasks use `git ls-files`: new or deleted files must be staged before they count.
- Always `PAGER=cat` for git.

## Committing

- One commit per working session, on `trunk`, after the gate passes. Never push or release.
- Include the session transcript as `doc/contributors/chats/NNN.md` and any plan or ADR the session produced.
- Conventional Commits, plain text, wrapped at 72. The body explains why this approach over alternatives, in prose (no lists, no markdown, no file inventories). Types: `lib/ext/sig` feat/fix/refactor/perf; `bin/tasks`/CI chore; `examples/` and `doc/` docs; `test/` test. End with the AI footer shown by `git log -n1`.

## Changelog

Keep a Changelog + SemVer. Only changes downstream app or library developers can observe: public APIs, behavior, breaking changes, deprecations, dependency changes. Not tests, docs, internal refactors, or tooling. Terse one-line entries under `## [Unreleased]`, which means "since the last tag": a change undone before the next tag removes its entry instead of adding a "Fixed" line. Never edit released sections.

## Definition of done

1. Every item in the plan is done, or explicitly deferred with a reason.
2. Behavior matches the cited Tauri source; deviations are justified by the precedence above and documented.
3. `bundle exec rake` passes from a clean build (`rm -rf tmp`), zero errors, zero warnings.
4. RDoc, RBS, `doc/`, README, and CHANGELOG updated where behavior changed.
5. A commit message is written (and the commit made, per Committing).
