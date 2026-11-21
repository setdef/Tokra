<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Changelog

All notable changes to tokra-process will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `tokra-process` gem: `Tokra::Plugins::Process.init`, registered with
  `Builder#plugin`, serves Tauri's process commands (`exit`, `restart`) for
  `@tauri-apps/plugin-process`: `exit(code)` asks the app to exit through
  `AppHandle#exit`, `relaunch()` restarts it through
  `AppHandle#request_restart`, and a `code` that is not an `i32` rejects
  with Tauri's argument error; a page with `withGlobalTauri` gets
  `window.__TAURI__.process` from Tauri's own `api-iife.js`, which the gem
  ships; it is pure Ruby

[Unreleased]: https://github.com/setdef/Tokra/commits/trunk/plugins/process
