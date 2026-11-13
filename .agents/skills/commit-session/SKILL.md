---
name: commit-session
description: Commits a finished step of Tokra work on trunk and pushes it - checks the definition of done, makes a Conventional Commit, lets the pre-push hook run the gate on exactly that commit, and stops short of tagging or releasing. Use when a step is done and the user wants it committed or pushed, or asks to wrap up, finish, or land the work.
---

<!-- SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com> -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Commit and push a step

AGENTS.md ("Committing", "Changelog", "Definition of done") sets the rules:
small, complete commits on `trunk`, no transcript, Conventional Commits
with a prose body and the AI footer, the gate before every push, never a
force-push, tag, or release. Follow them; this skill is the order of
operations. If your instructions say an orchestrator commits, stop after
step 1 and hand over the message instead.

## 1. Check the definition of done

Walk the step's plan item by item. Each is done, or deferred with a
written reason in the plan. Confirm the CHANGELOG, RDoc, RBS, and docs
cover every observable change. Run the tests the change touches, and
`bundle exec rake rubocop:autocorrect_all`.

## 2. Commit

```sh
git add -A                       # rake tasks read git ls-files
PAGER=cat git status
PAGER=cat git diff --cached --stat
PAGER=cat git log -n1            # copy the AI footer from here
git commit -F <message file>
```

The message: a Conventional Commits subject (type per AGENTS.md), a blank
line, then a body wrapped at 72 columns that explains in prose why this
approach beat the alternatives. No lists, no Markdown, no file inventory.
End with the AI footer exactly as `git log -n1` shows it.

## 3. Push through the gate

```sh
git fetch origin && git rebase origin/trunk
git push origin trunk
```

The pre-push hook (`.githooks/pre-push`, which `bin/setup` installs) runs
the gate, `bundle exec rake`, on the commit you push. It passes with zero
errors and zero warnings, or nothing is pushed: fix the cause, commit, and
push again. Never pass `--no-verify`. If a gemspec, a `Cargo.toml`, or an
`extconf.rb` changed, run `bundle exec rake package:install` before the
push too.

For the clean build the definition of done asks for, remove build output
before the push:

```sh
rm -rf tmp plugins/*/tmp
find lib/tokra plugins/*/lib -name '*.bundle' -delete
```

## 4. Stop

Do not tag or release. Report the commit hash, the gate's counts, and
anything deferred. CI runs the gate on the systems yours is not; if it
turns `trunk` red, fixing or reverting that commit comes before any other
work.
