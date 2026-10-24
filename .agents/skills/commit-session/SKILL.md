---
name: commit-session
description: Finishes a Tokra working session - runs the clean-build gate, stages the work, exports the session transcript to doc/contributors/chats/NNN.md, and makes the single Conventional Commit AGENTS.md asks for, without pushing. Use when the work is done and the user wants it committed, or asks to wrap up, finish, or commit the session.
---

<!-- SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com> -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Commit a session

AGENTS.md ("Committing", "Changelog", "Definition of done") sets the rules:
one commit per session on `trunk`, transcript included, Conventional Commits
with a prose body and the AI footer, never push or release. Follow them;
this skill is the order of operations. If your instructions say an
orchestrator commits, stop after step 3 and hand over the message instead.

## 1. Check the definition of done

Walk the session's plan item by item. Each is done, or deferred with a
written reason in the plan. Confirm the CHANGELOG, RDoc, RBS, and docs
cover every observable change.

## 2. Run the clean-build gate

Remove build output and run the full gate. If a gemspec, a `Cargo.toml`,
or an `extconf.rb` changed, also run `bundle exec rake package:install`.

```sh
bundle exec rake rubocop:autocorrect_all
git add -N <new files>        # rake tasks read git ls-files
rm -rf tmp plugins/*/tmp
find lib/tokra plugins/*/lib -name '*.bundle' -delete
bundle exec rake
```

It passes with zero errors and zero warnings, or you do not commit. Note
the test counts for the report.

## 3. Export the transcript

```sh
bundle exec ruby .agents/skills/commit-session/scripts/export_transcript.rb --next \
  --copyright "$(git config user.name) <$(git config user.email)>"
```

The script finds the current Claude Code session (from
`CLAUDE_CODE_SESSION_ID`, or the newest transcript for this directory),
writes the next `doc/contributors/chats/NNN.md`, and prints its path. Pass
a transcript path to export another session (a subagent's transcript lives
under the session's `subagents/` folder), `--title` for a heading, or
`--output PATH`. The copyright holder comes from `--copyright`, or from
`GIT_AUTHOR_NAME` and `GIT_AUTHOR_EMAIL`; the script stops with exit 2 if
neither is set. It never overwrites a file and never runs git. Run with
`--help` for the options and exit codes. Read the result before staging it:
it records every user message, so remove nothing silently, but tell the
user if it holds something they may not want committed.

## 4. Stage and commit

```sh
git add -A
PAGER=cat git status
PAGER=cat git diff --cached --stat
PAGER=cat git log -n1            # copy the AI footer from here
git commit -F <message file>
```

The message: a Conventional Commits subject (type per AGENTS.md), a blank
line, then a body wrapped at 72 columns that explains in prose why this
approach beat the alternatives. No lists, no Markdown, no file inventory.
End with the AI footer exactly as `git log -n1` shows it.

## 5. Stop

Do not push, tag, or release. Report the commit hash, the gate's counts,
and anything deferred.
