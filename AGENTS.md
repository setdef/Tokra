<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# AGENTS.md

## Project

Tokra is a 1:1 port of Tauri to Ruby (>= 4.0.1): desktop apps with a Ruby backend and a web frontend. Rust (rb_sys + magnus, in `ext/`) is a thin binding over tao and wry; Ruby owns all logic (ADR 001). First-party plugins live in `plugins/`. Standalone crate bindings are moving to Ferro, a separate project of 1:1 crate-binding gems.

Pre-1.0, zero external users. Prefer good design over backward compatibility; record every breaking change in CHANGELOG.md.

## Design precedence

1. **Ruby the language.** What Ruby can and cannot express. Rust constructs with no Ruby meaning (lifetimes, ownership, Cargo feature flags) are translated, not ported. A feature Tauri gates behind a Cargo feature is simply supported when it adds behavior; one that relaxes a safety default stays off, and is exposed only as a code-level opt-in named after the feature.
2. **Tauri fidelity.** Names, class structure, error messages, wire formats, and behavior MUST match Tauri's Rust source. Do not invent "more Ruby-like" APIs.
3. **Ruby culture.** Idioms yield to 1 and 2.

The authority is the pinned submodule `vendor/tauri` (`git submodule update --init` if empty). For Rust dependencies (wry, tao, arboard, magnus, rb-sys), read the exact locked source Cargo already downloaded; `cargo metadata --format-version 1` gives each package's `manifest_path`. For anything else, such as Tauri's official plugins, use the upstream repository (https://github.com/tauri-apps/plugins-workspace) at the version being ported, and fetch it into an ignored scratch directory if you need it locally. Never guess at a reference's contents. Cite the file and lines you ported, and add an SPDX snippet (Apache-2.0 OR MIT) around any code or prose derived from it.

## How to work

- Research before designing: read the Tauri source and the relevant ADRs and design documents in `doc/contributors/` first.
- Root-cause every fix. If you cannot explain why a change fixed the symptom, it is not a fix.
- Write tests first. A test must fail if the code it covers is deleted or mutated, and must exercise real collaborators, not stubs that hide missing behavior.
- Design in the spirit of Kent Beck (small steps, Implementation Patterns), Freeman & Pryce (tests drive interfaces), Sandi Metz (duplication over the wrong abstraction), Rebecca Wirfs-Brock (responsibility-driven roles), Martin Fowler (refactor in behavior-preserving steps), and Matz (programmer happiness). Write prose in the style of `doc/contributors/documentation_style.md`.
- Skills in `.agents/skills/` hold the detailed workflows: `port-tauri-feature` before porting, `audit-parity` before approving a diff, `commit-session` to commit and push a finished step. Mutation testing is not automated yet, so reviewers check by hand that each changed behavior has a test that fails when its code is reverted.

## Ruby, RBS, and docs

- `Data.define` for value objects (`class Foo < Data.define(...)`), `class` for entities.
- Every Ruby method has an RBS signature in `sig/` mirroring `lib/`. No `untyped`, no comments in `.rbs`. For `Data.define` classes, declare `self.new` instead of `initialize` (Steep mis-checks `initialize` there); plain classes declare `initialize` as usual.
- Inside `module Tokra`, a bare `Process` names `Tokra::Process` (Tauri's `process` module), so `lib/` and plugin code write `::Process` or `Tokra::Process`; RuboCop's `Lint/ConstantResolution` and `test/tasks/test_top_level_constants.rb` enforce it (Plan 039, 2026-10-28).
- RDoc (never YARD) in `.rb` files only. Wrap SPDX headers in `#--` / `#++`.
- Plans live in `doc/contributors/plan/`, design documents in `doc/contributors/design/`.
- `examples/` is documentation for app developers: small, focused, and copyable. Never put test hooks, probes, or fixtures there; those live under `test/`.

## Commands

- Run Ruby with `bundle exec ruby`. Run tests with `bundle exec rake test`. Never `ruby -Ilib:test`.
- Real-window tests (everything in `test/integration/`, any test naming `RealApp` or `NativeEventLoop`, and the plugin tests `tasks/real_windows.rb` names) open real windows, menus, dialogs, and notifications, and use the session's clipboard, in the session that runs them. `rake test:gui` runs them, first in the gate, on every system: `test:keyboard`, `test:real_windows`, and `test:real_windows:plugins`, and then the console set in `test:console` (Plan 061). `test:core`, `plugins:test`, and a plugin's own `rake test` leave them out, so those open nothing on the desktop you are working at. Only those three tasks, `test:console`'s subtasks, and `test:replay` set `TOKRA_REAL_WINDOWS_RUN`, and without it `RealApp.launch` and `NativeEventLoop.shared` raise, so a test the file rule misses fails instead of opening a window. Tests that open a real menu or bring a fixture to the front go in `test/integration/keyboard/` and call `KeyboardNotice.take_the_keyboard_for_the_run` before the launch, which holds the `desktop_input_lock` gem's lock from the first such test to the end of the `test:keyboard` process, so a run speaks once, not once per test (Plan 046). Only tests a person's keyboard or mouse could fail speak, all in one span; `test:console` holds its one span with the block form, `KeyboardNotice.taking_the_keyboard { ... }`. On a Mac outside CI (`CI` unset) the lock also shows a banner and says aloud when to step away and come back; `DESKTOP_INPUT_QUIET=1` or `TOKRA_QUIET=1` silences it but still locks.
- The console set, the files `RealWindows::CONSOLE` names, runs only in `rake test:console`, which `test:gui` runs last; every other real-window task leaves it out (Plan 057). Its tests are plugin tests a person's click could fail: a click on one of their dialog sheets would end it. So `test:console` holds the desktop input lock around only those tests, once per run, with its banner and spoken notice; a console test that took the lock itself would wait on its own parent forever.
- `bundle exec rake` is the gate: tests, RuboCop, Steep, RBS parity, RDoc coverage, REUSE, Clippy, fmt, and a packaging check that loads each built gem outside the repository. It must pass with zero errors and zero warnings; every cargo step, the extension compiles included, fails on any rustc, Clippy, or Cargo warning. Every `unsafe` block or impl needs a `// SAFETY:` comment citing the source that makes it sound. Run `bundle exec rake rubocop:autocorrect` first to save time.
- `bin/setup` installs the tools `mise.toml` pins, the bundle, on a Debian or Ubuntu machine the Linux packages of ci.yml it lacks (through `bin/linux-env`, with no root; Plan 068), and a pre-push hook, `.githooks/pre-push`, which runs the gate on the commit you push; run it again whenever you like. The hook refuses a push unless the commit checked out is the one pushed, with nothing uncommitted and nothing untracked, since the gate tests the working tree. Never bypass it (`--no-verify`). A commit runs only `bundle check` (Plan 061). On Windows, run `bin/setup.ps1` from PowerShell instead: it runs `bin/setup` in the bash of Ruby's MSYS2, which adds Rust's GNU host toolchain and libclang, and the hook runs the gate through `bin/windows-env`, which sets what CI's Windows job sets for Rust and bindgen; run any task by hand the same way (`bin/windows-env bundle exec rake test:core`). None of this has yet run on a Windows machine (Plan 061).
- CI (`.github/workflows/ci.yml`) runs the same gate on Linux (under Xvfb, so the real-window tests run), macOS, and Windows for every supported Ruby. When a Ruby release ships, add it to the matrix; remove one only at its end of life.
- `bundle exec rake test:linux` runs CI's Linux job from a Mac or Windows: the bundle install and gate commands it reads from ci.yml, under Xvfb and D-Bus with `CI=true`, in a Docker container, so tests that skip off Linux fail here instead of on CI (Plan 058). It is not in the gate; run it before a push that could behave differently on Linux. It builds `tasks/linux/Dockerfile` (Ubuntu 24.04, with the Rust pin, Rust components, apt packages, REUSE version, and Bundler version it reads from `mise.toml`, ci.yml, and `Gemfile.lock`; Ruby's version and checksum live in the Dockerfile, and a test checks them against `mise.toml` and ci.yml's matrix), mounts the checkout read-only, and copies in only what git tracks, as the working tree has it, so stage new files first. It comes close to CI, not exactly: arm64 rather than x86_64, a fixed `ubuntu:24.04` where `ubuntu-latest` moves, a submodule copied as its working tree has it (it says when that is not the recorded commit), and `TOKRA_QUIET=1` added. Each checkout has its own image, container, and named volumes for Cargo, the gems, `target/`, and `tmp/`, keyed by the checkout's path, so checkouts run at once and a second run is warm, which also makes it incremental; `CLEAN=1` empties `target/` and `tmp/` first. `rake "test:linux[TASK,...]"` runs only those tasks there; `rake test:linux:prune` removes the volumes and image of each checkout that is gone.
- Approved exceptions live in `rbs_exceptions.rb` and `clippy_exceptions.rb`; adding one needs a justification that it is impossible otherwise.
- Each native gem is its own Cargo workspace with a committed `Cargo.lock`, built with `--locked`. After changing a gemspec, `Cargo.toml`, or `extconf.rb`, and before any release, also run `bundle exec rake package:install`, which compiles every gem from its packaged sources.
- Rake tasks use `git ls-files`: new or deleted files must be staged before they count.
- Always `PAGER=cat` for git.

## Committing

- Work on `trunk`, never on a branch, in small steps: sync with `origin/trunk`, make one complete change that keeps the gate green, and commit it with any plan or document it produced. Your unpushed commits are your branch, and it lives for minutes, not days. A worktree's branch is only a name for its unpushed commits: push it as `HEAD:trunk`.
- The gate runs before a push, on exactly the commit you push. Push `trunk` once it passes, and never to find out whether CI will: CI is for the systems your machine is not. A red `trunk` comes before any other work: fix it or revert the commit at once.
- Never force-push, tag, or release. Tags and releases are the maintainer's, and are scripted rake tasks, never hand-run git (Plan 059). Each gem, tokra at the root and each plugin in `plugins/`, has its own version, CHANGELOG, and tags named for it, such as `tokra/v0.1.0` and `tokra-dialog/v0.1.0`; Bundler's `gem_tasks` are not loaded. `rake bump:<gem>:patch` (or `:minor`, `:major`, `:exact[0.2.0]`, or `:current` for a new plugin's first version; a label such as `minor[beta]` makes an opt-in prerelease) sets the gem's version everywhere, releases its CHANGELOG's Unreleased entries, runs the gate, and commits `chore(<gem>): release X.Y.Z`; a tokra release that moves its minor version also moves every plugin's `tokra ~>` floor to it. Versions are plain 0.x before 1.0, written as SemVer in `version.rb`, tags, and CHANGELOG headings (`0.2.0-beta.1` for an opt-in preview, which RubyGems stores as `0.2.0.pre.beta.1`). `rake release:<gem>:tag` tags the release commit and pushes only the tag; `rake release:<gem>:push[X.Y.Z]` pushes a tagged version to RubyGems.org, built from a clean checkout of the tag; `rake release:<gem>` builds, pushes trunk, tags, and pushes the gem in one step.
- Never commit session transcripts; `doc/contributors/chats/` is a closed archive.
- Conventional Commits, plain text, wrapped at 72. The body explains why this approach over alternatives, in prose (no lists, no markdown, no file inventories). Types: `lib/ext/sig` feat/fix/refactor/perf; `bin/tasks`/CI chore; `examples/` and `doc/` docs; `test/` test. End with the AI footer shown by `git log -n1`.

## Changelog

Each gem keeps its own `CHANGELOG.md`: tokra's at the root, each plugin's in its folder. Keep a Changelog + SemVer. Only changes downstream app or library developers can observe: public APIs, behavior, breaking changes, deprecations, dependency changes. Not tests, docs, internal refactors, or tooling. Terse one-line entries under `## [Unreleased]`, which means "since the gem's last tag": a change undone before the next tag removes its entry instead of adding a "Fixed" line. Never edit released sections.

## Definition of done

1. Every item in the plan is done, or explicitly deferred with a reason.
2. Behavior matches the cited Tauri source; deviations are justified by the precedence above and documented.
3. `bundle exec rake` passes from a clean build (`rm -rf tmp`), zero errors, zero warnings.
4. RDoc, RBS, `doc/`, README, and CHANGELOG updated where behavior changed.
5. The work is committed and pushed, per Committing.
