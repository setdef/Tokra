<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `Tokra::Webview` wrapper class with per-webview `ResourceTable`
- `Tokra::Window` wrapper class with per-window `ResourceTable`
- `Tokra::ResourceTable` placeholder for Phase 2.1 resource management
- `Invoke#webview` accessor returns calling webview (now required parameter)
- `AppHandle#windows` returns all managed windows
- `AppHandle#get_window(label)` fetches window by label
- `AppHandle#get_webview(label)` fetches webview by label
- `AppHandle#resources_table` returns app-level fallback table
- `Manager#resources_table` abstract method for unified interface

### Changed

### Fixed

### Removed

[Unreleased]: https://git.sr.ht/~kerrick/tokra/refs/HEAD