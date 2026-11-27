<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Security policy

## Report a vulnerability privately

Report a vulnerability in Tokra through GitHub's private vulnerability reporting, never on the [forum](https://forum.setdef.com/c/tokra), in an email thread, or anywhere else others can read it:

1. Open [the repository's Security tab](https://github.com/setdef/Tokra/security) and choose **Report a vulnerability**, or go straight to [a new private advisory](https://github.com/setdef/Tokra/security/advisories/new).
2. Fill in the form. Only the project's maintainers can see what you send.

If you aren't sure that a problem is a vulnerability, report it privately anyway.

## What to include

- The Tokra version, from `bundle info tokra`.
- Your system: its operating system and processor, and the output of `ruby -v` and `rustc -V`.
- How to reproduce the problem: the code or command you ran and what happened.

## Which versions get fixes

[The README's Compatibility section](README.md#compatibility) lists the systems, Ruby versions, and Rust versions Tokra runs on. It makes no promise that an earlier release gets a fix. A fix ships in a new release, so install [the latest `tokra` release](https://github.com/setdef/Tokra/releases).
