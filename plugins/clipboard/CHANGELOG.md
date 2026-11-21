<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Changelog

All notable changes to tokra-clipboard will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `tokra-clipboard` gem: `Tokra::Plugins::Clipboard.init`, registered with
  `Builder#plugin` and taking no config, manages a
  `Tokra::Plugins::Clipboard::Clipboard` (reachable as `app.clipboard`,
  Ractor-shareable) and serves Tauri's `clipboard-manager` commands
  (`read_text`, `write_text`, `read_image`, `write_image`, `write_html`,
  `clear`); every failure raises or rejects with `Error::Clipboard` or
  Tauri's argument error, and `read_text` raises on an empty clipboard; a
  page with `withGlobalTauri` gets `window.__TAURI__.clipboardManager` from
  Tauri's own `api-iife.js`, which the gem ships; it is pure Ruby and
  depends on `ferro-arboard`
  0.1.0 (arboard 3.7.0, Wayland included), which apps take from its
  git tag until it is on RubyGems.org

[Unreleased]: https://github.com/setdef/Tokra/commits/trunk/plugins/clipboard
