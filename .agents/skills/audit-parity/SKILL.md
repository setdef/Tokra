---
name: audit-parity
description: Audits a Tokra commit, branch, or diff against the Tauri source it ports, checking fidelity, failure paths, tests, packaging, and docs, and reports a verdict with a findings table (BUG, PARITY, TEST-GAP, DOC, NIT) citing file:line and the Tauri source. Use when asked to review, audit, or verify a change for Tauri parity, or before approving a port.
---

<!-- SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com> -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Audit a change for Tauri parity

You are a reviewer, not the author. Read the change, then the source it
claims to port, and report what is wrong. Do not fix anything unless asked.
AGENTS.md defines the precedence and the definition of done you audit
against.

## 1. Scope the change

```sh
PAGER=cat git log --oneline <base>..<head>
PAGER=cat git diff --stat <base>..<head>
PAGER=cat git diff <base>..<head> -- lib ext plugins sig
```

Read the plan the change executes (`doc/contributors/plan/`) and the ADRs it
cites. List every behavior the change adds or alters; each one gets checked.

## 2. Verify against the source

For each behavior, open the cited Tauri file (`vendor/tauri`, the locked
crate from `cargo metadata`, or plugins-workspace at the ported version) and
compare. Use [references/parity-checklist.md](references/parity-checklist.md)
as the checklist: names, verbatim messages,
wire formats, ordering, encodings, failure paths, security. A citation that
does not say what the change claims is itself a finding.

Check the cross-cutting failure modes this project has hit before:

- An invoke or request that can hang (an exception, a serialization error,
  or a dropped responder on any path).
- A frontend-reachable input that panics native code.
- A method declared in `sig/` that only an ancestor stubs, or a test double
  that implements a method the real class lacks.
- A file the gem loads at run time that `spec.files` misses, or a crate
  that only builds inside the repository workspace.
- Code after a call that never returns.
- Tauri-derived code or prose without an SPDX snippet and citation.
- A deviation not recorded in the plan and the ADR or RDoc a user reads.
- Plan items silently skipped, or "done" without the clean-build gate.

## 3. Run the manual mutation check

Automated mutation testing is deferred (Plan 017). Do it by hand instead:

1. For each new or changed behavior, name the test that fails if the line is
   deleted or a key constant or branch changes. No such test is a TEST-GAP.
2. Spot-check a sample, at least one per changed file: revert or alter the
   line, run only the named test with `bundle exec rake test:core
   N=/test_name/` (a plugin test from its directory with
   `bundle exec rake test N=/test_name/`), confirm it fails, then
   restore the line and confirm `git diff` shows nothing you introduced.
3. Report each spot-check: the line, the mutation, the test, and whether it
   failed.

## 4. Run the gates

Run the clean-build gate from AGENTS.md. Report test counts, and any error
or warning. A gate you could not run is UNVERIFIED.

## 5. Report

Give a verdict, a findings table, the mutation spot-checks, the gate
results, and what you could not verify. Order findings by severity. Each
finding cites `path:line` in the change and the Tauri `path:line` it
diverges from, and proposes a fix.

```markdown
**Verdict:** APPROVE | APPROVE WITH NITS | CHANGES REQUESTED | REJECT
<two or three sentences: is the port faithful, and what matters most>

Sources read: vendor/tauri @ <commit>; <crate> <version>; plugins-workspace @ <commit>

| # | Severity | Where | Tauri source | Finding | Fix |
|---|---|---|---|---|---|
| 1 | BUG | lib/tokra/ipc/invoke.rb:93 | ipc/mod.rs:265-276 | A value whose to_json raises leaves the invoke pending | Mark responded only after serialization |

Mutation spot-checks: | Line | Mutation | Test | Failed? |
Gates: clean build pass/fail, runs, assertions, failures, errors, skips, warnings
UNVERIFIED: <claim>: <why not checked> (<what would check it>)
```

| Severity | Meaning |
|---|---|
| BUG | Wrong behavior a user can hit: hang, crash, data loss, security hole, broken install |
| PARITY | Behaves differently from Tauri without a documented, justified deviation |
| TEST-GAP | Behavior no test would catch if deleted or mutated, or a test that exercises only a stub |
| DOC | RDoc, RBS, CHANGELOG, ADR, or plan is missing, wrong, or contradicts Tauri's docs |
| NIT | Style or clarity; never blocks |

Mark anything you inferred but did not read or run as UNVERIFIED, and say
what would verify it.
