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
- `Tokra::ResourceTable` with full lifecycle management:
  - `add(resource)` returns unique integer ID
  - `get(rid)` retrieves resource by ID
  - `take(rid)` removes without calling close
  - `close(rid)` removes and calls resource.close
  - `replace(rid, resource)` updates existing slot
  - `clear` removes all resources
  - `names` enumerator for debugging
- `Tokra::Resource` mixin module (mirrors Tauri's Resource trait)
- `Tokra::Image` data class for RGBA images with ResourceTable integration
- `Tokra::Error` base class with nested `BadResourceId` exception
- `Invoke#webview` accessor returns calling webview (now required parameter)
- `AppHandle#windows` returns all managed windows
- `AppHandle#get_window(label)` fetches window by label
- `AppHandle#get_webview(label)` fetches webview by label
- `AppHandle#resources_table` returns app-level fallback table
- `Manager#resources_table` abstract method for unified interface
- `Tokra::PluginStore` routes `plugin:NAME|command` invokes to the named plugin
- `AppHandle#plugin(plugin)` registers a plugin for IPC dispatch
- `AppHandle#remove_plugin(name)` unregisters a plugin by name
- Plugin `extend_api` receives the bare command name (prefix stripped)
- Unhandled IPC commands are rejected with `Command <name> not found`
- Core `resources` plugin, registered automatically:
  - `plugin:resources|close` closes a resource (webview, then window, then app)
- Core `image` plugin, registered automatically:
  - `plugin:image|new` stores an RGBA image and resolves its resource ID
  - `plugin:image|rgba` resolves the stored image's bytes
  - `plugin:image|size` resolves the stored image's width and height
  - `plugin:image|from_bytes` decodes PNG or ICO bytes into a stored image
  - `plugin:image|from_path` decodes a PNG or ICO file into a stored image
- `Tokra::Image.from_bytes` decodes PNG or ICO bytes to raw RGBA
- `Tokra::Image.from_path` decodes a PNG or ICO file to raw RGBA
- `Tokra::Error::Image` raised when image bytes cannot be decoded

### Changed

### Fixed

### Removed

[Unreleased]: https://git.sr.ht/~kerrick/tokra/refs/HEAD