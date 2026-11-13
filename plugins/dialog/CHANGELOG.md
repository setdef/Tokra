<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Changelog

All notable changes to tokra-dialog will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `tokra-dialog` gem: `Tokra::Plugins::Dialog::Plugin.new(app)` manages a
  `Tokra::Plugins::Dialog::Dialog` (reachable as `app.dialog`) with Tauri's
  `MessageDialogBuilder` and `FileDialogBuilder`, serves Tauri's dialog
  commands (`open`, `save`, `message`, `ask`, `confirm`) for
  `@tauri-apps/plugin-dialog`, and replaces the page's `window.alert` and
  `window.confirm` with them; dialogs start on the main thread and are
  awaited off it, so the window keeps running; the builders' `set_parent`
  and `parent` take a `Tokra::Window`, and the commands parent each dialog
  to the calling window as Tauri does, except on Wayland (ferro-rfd binds
  no Wayland handle), so on macOS each is a sheet on that window; picked
  paths join no scope; it is pure Ruby and depends on `ferro-rfd`
  0.1.0 (rfd 0.17.2), which apps take from its git tag until it is
  on RubyGems.org

[Unreleased]: https://github.com/setdef/Tokra/commits/trunk/plugins/dialog
