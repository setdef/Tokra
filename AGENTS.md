<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# AGENTS.md

## Project Identity

Project Name: tokra

Description: A port of Tauri to Ruby, enabling you to build desktop applications with web technologies.

Architecture: [@/oop] for te [@/rubyist].

## Stability & Compatibility

- **Project Status:** Pre-1.0. 
- **User Base:** Zero external users.
- **Breaking Changes:** Backward compatibility is **NOT** a priority. Since there are no external users, you are encouraged to refactor APIs for better ergonomics and performance even if it breaks existing code.
- **Requirement:** All breaking changes **MUST** be explicitly documented in the [CHANGELOG.md](CHANGELOG.md)'s **Unreleased** section to ensure transparency.

## 1. Standards

### STRICT REQUIREMENTS

- Every file MUST begin with an SPDX-compliant header. Use `AGPL-3.0-or-later` for code; `CC-BY-SA-4.0` for documentation. `reuse annotate` can help you generate the header. **For Ruby files**, wrap SPDX comments in `#--` / `#++` to hide them from RDoc output.
- Every line of Ruby MUST be covered by tests that would stand up to mutation testing.
  - Tests must be meaningful and verify specific behavior or rendering output; simply verifying that code "doesn't crash" is insufficient and unacceptable.
- **Pre-commit:** Use `bundle exec rake` to ensure commit-readiness. See Tools for detailed instructions.
- **Git Pager:** ALWAYS set `PAGER=cat` for ALL `git` commands (e.g., `PAGER=cat git diff`). This is mandatory.

### Tools

- **ALWAYS** run `bundle exec ruby` to ensure libraries are loaded. **NEVER** run `ruby -Ilib:test ...` directly.
- **ALWAYS use `bundle exec rake`** for running tests, linting, or checking compilation.
  - **Usage:**
    - Runs default task (test + lint + typecheck): `bundle exec rake`. Do this before considering a commit ready.
    - Runs specific task: `bin/agent_rake test:ruby` (for example). Do not run specific rake tasks for commit readiness.
- **Setup:** `bin/setup` must ensure all dependencies are installed.
- **Rake:** Our rake tasks use `git ls-files`, so errors happen when you move or delete files. In this case, ask the user to stage changes for you.

### Ruby Standards

- Use `Data.define` for all value objects. (Prefer `class Foo < Data.define()` over `Foo = Data.define() do`).
- Use `class` for all entities.
- Define types in `.rbs` files. Don't use `untyped` just because it's easy; be comprehensive and accurate.
  - Do not include `initialize` in `.rbs` files; use `self.new` for constructors instead.
  - **Every** ruby class/method must have a corresponding `.rbs` type definition.
- Every public Ruby class/method must be documented for humans in RDoc (required)--**not** YARD--or markdown files.
  - RDoc documentation **must** be written in `.rb` files, not their corresponding `.rbs` files. `.rbs` files should have **ZERO** comments.
- Every significant architectural and design decision must be documented for contributors in markdown files. Mermaid is allowed.

## 2. Directory Structure Convention

The project follows a standard Gem layout with `examples/` added to show other rubyists how to `require` and use `lib/tokra`.

## 3. Configuration & Tooling

### Development Environment

- **Scripting Preference:** Simple `sed` or shell one-liners are fine. When a one-off script grows to multiple lines of logic, prefer a temporary rake task or `ruby -e '...'` over a multi-line shell script in a string. Ruby's `File.read`/`File.write`, `Dir.glob`, and regex handle complex transformations more cleanly.

### Documentation

- **The `doc/` folder contains source markdown files** that are included in RDoc output.
- Documentation should separate "User Guide" (Ruby API for TUI developers) from "Contributor Guide" (Ruby/Rust/Magnus internals).
  - Files within `doc/contributors/` are for library developers.
  - Files within `doc/` outside of `conttributors/` are for application developers and users of this RubyGEm.
- **Style Guide:** You **MUST** follow the [Documentation Style Guide](doc/contributors/documentation_style.md). This dictates the Alexandrian/Zinsser prose style and strict RDoc formatting required for all public API documentation.
- DON'T write .md files for something RDoc (Ruby) can generate. DO use RDoc for documentation.


## 4. Committing

- Who commits: DON'T stage (DON'T `git add`) unless explicitly instructed. DON'T commit unless explicitly instructed. DO suggest a commit message when you finish, even if not instructed..
- When: Before reporting the task as complete to the user, suggest the commit message.
- What: Consider not what you remember, but EVERYTHING in the `git diff` and `git diff --cached`.
- **Format:**
    - Format: Use [Conventional Commits](https://www.conventionalcommits.org/).
    - Body: Explanation if necessary (wrap at 72 chars).
        - Explain why this is the implementation, as opposed to other possible implementations.
        - Skip the body entirely if it's rote, a duplication of the diff, or otherwise unhelpful.
        - **DON'T list the files changed or the edits made in the body.** Don't provide a bulleted list of changes. Use prose to explain the problem and the solution.
        - **DON'T use markdown syntax** (no backticks, no bolding, no lists, no links). The commit message must be plain text.
- **Type conventions by directory:**
    - `lib/`, `exe/`, `sig/`: Use `feat`, `fix`, `refactor`, `perf` as appropriate.
    - `bin/`, `tasks/`, `.builds/`, CI/CD: Use `chore` for tooling internal to developing this gem. Use `feat`/`fix` for changes that affect downstream users.
    - `examples/`: Always `docs` (documentation by example).
    - `test/`: Use `test` for new/changed tests, or match the type of the code being tested.
    - `doc/`: Always `docs`.
  
### 5. Changelog

- Follow [Semantic Versioning](https://semver.org/)
- Follow the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) specification.
- **What belongs in CHANGELOG:** Only changes that affect **executable users** or **higher-level library developers** who use or depend on `tokra`:
    - New public APIs or CLI flags
    - Backwards-incompatible type signature changes, or behavioral additions to type signature changes
    - Observable behavior changes (rendering, styling, layout)
    - Deprecations and removals
    - Breaking changes
- **What does NOT belong in CHANGELOG:** Internal or non-behavioral changes that don't affect downstream users:
    - Test additions or improvements
    - Documentation updates, RDoc fixes, markdown clarifications
    - Refactors of internal code
    - New or modified example code
    - Internal tooling, CI/CD, or build configuration changes
    - Code style or linting changes
    - Performance improvements that affect applications
- Changelogs should be useful to downstream developers (both app and library developers), not simple restatements of diffs or commit messages.
- The Unreleased section MUST be considered "since the last git tag". Therefore, if a change was done in one commit and undone in another (both since the last tag), the second commit should remove its changelog entry.
- **Location:** New entries ALWAYS go in `## [Unreleased]`. Never edit past version sections (e.g., `## [0.4.0]`)—those are frozen history.

## 6. Definition of Done (DoD)

Before considering a task complete and returning control to the user, you **MUST** ensure:

0. **Production Ready:** RBS types are complete and accurate (no `untyped`), errors are handled with good DX, documentation follows guidelines, high code quality (no "pre-existing debt" excuses).
1.  **Default Rake Task Passes:** Run `bundle exec rake` (no args). Confirm it passes with ZERO errors **and ZERO warnings**.
  - You will save time if you run `bundle exec rake rubocop:autocorrect` first.
  - If you think the Rake is looking for deleted files, STOP EVERYTHING and tell the user.
2.  **Documentation Updated:** If public APIs or observable behavior changed, update relevant RDoc, RBS, `doc/` files, and/or `README.md`.
3.  **Changelog Updated:** If public APIs, observable behavior, or gemspec dependencies have changed, update [CHANGELOG.md](CHANGELOG.md)'s **Unreleased** section.
4.  **Commit Message Suggested:** You **MUST** ensure the final message to the user includes a suggested commit message block. This is NOT optional.
  - You MUST also check `git log -n1` to see the current standard AI footer ("Generated  with" and "Co-Authored-By") and include it in your suggested message.
