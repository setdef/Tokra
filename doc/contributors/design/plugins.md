<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Plugins

This document says how Tokra's plugins are built and shipped. It is for
Tokra's contributors. Each plugin's README covers its install, usage,
and differences from Tauri.

## Which plugins Tokra ports

Tokra ports every official Tauri plugin that has a desktop side, with
Tauri's commands, payloads, and file formats, `fs`, `http`, and `store`
included. A plugin has two callers, the app's Ruby and the page, and
Ruby's `File` and `Net::HTTP` serve only the first: a page that calls
`@tauri-apps/plugin-fs` or `@tauri-apps/plugin-http` fails without a
plugin to answer it. Where a plugin writes a file, it writes Tauri's
format, so a `store` reads the JSON files Tauri's `store` wrote
(`plugins/store/src/lib.rs` in `tauri-apps/plugins-workspace` at
`d4613ff0`), and an app can move between Tauri and Tokra and keep them.
A plugin with no desktop side is out of scope with the rest of mobile.
This follows from ADR 008, and was recorded on 2026-11-13 by an agent
applying AGENTS.md's design precedence, with the maintainer accountable.

`fs` and `http` are large, and both need Tauri's scopes, which wait on
the access-control port ([config.md](config.md), "Access control"). No
plan has ported `fs`, `http`, or `store` yet. Each plugin's plan
enumerates the upstream plugin's commands and formats, and its tests
drive them through the IPC as the page does.

