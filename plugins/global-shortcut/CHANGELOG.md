<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `tokra-global-shortcut` gem: `Tokra::Plugins::GlobalShortcut::Builder`
  (with `with_shortcut`, `with_shortcuts`, `with_handler`, and `build`),
  whose plugin is registered with `Builder#plugin` and takes no config,
  manages a `GlobalShortcut` (reachable as
  `app.global_shortcut`) with Tauri's `register`, `on_shortcut`,
  `register_multiple`, `on_shortcuts`, `unregister`, `unregister_multiple`,
  `unregister_all`, and `is_registered`, and serves Tauri's commands for
  `@tauri-apps/plugin-global-shortcut`, sending each press through the
  page's Channel; handlers run on a thread of their own; a page with
  `withGlobalTauri` gets `window.__TAURI__.globalShortcut` from Tauri's own
  `api-iife.js`, which the gem ships; it is pure Ruby and
  depends on `ferro-global-hotkey` 0.1.0 (global-hotkey 0.9.0), which
  apps take from Ferro's git repository until it is on RubyGems.org

[Unreleased]: https://github.com/setdef/Tokra/commits/trunk/plugins/global-shortcut
