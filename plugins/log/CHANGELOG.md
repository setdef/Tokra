<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Changelog

All notable changes to tokra-log will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `tokra-log` gem: `Tokra::Plugins::Log::Builder#build` makes Tauri's log
  plugin for `Builder#plugin`, whose setup attaches a
  `Tokra::Plugins::Log::Logger` as the process's one logger
  (`Log.attach_logger`, `Log.logger`, `Log.max_level`; a second attach
  raises `Log::SetLoggerError`), with `skip_logger` and `split` as
  Tauri's; the plugin serves the `log` command `@tauri-apps/plugin-log`
  invokes (records targeted `webview:<location>`, logged to `Log.logger`,
  with Tauri's argument rejections), and the logger writes
  `[date][time][target][LEVEL] message` lines in UTC to Tauri's default
  targets (standard output and the app's log directory) or to
  `TargetKind::Stdout`, `Stderr`, `Folder`, `LogDir`, `Webview` (a
  `log://log` event with the formatted line and its `LogLevel`), and
  `Dispatch` (a Logger of the app's own); with Tauri's `level` (default
  `:trace`), `filter` and `Target#filter` on a record's `Metadata`,
  `format`, `clear_format`, and `Target#format` on the formatted line,
  `timezone_strategy`, and log files named for the app that rotate at
  `max_file_size` (default 40000 bytes) by `RotationStrategy` (default
  `KeepOne`) into dated archives; `TimezoneStrategy#get_now` reads the
  time crate's now through `ferro-time` 0.1.0; the logger takes Logger's
  `trace` through `fatal` and `add`; `level_for` and `with_colors` raise
  `NotImplementedError`; like Tauri's, the plugin takes no config, and a
  page with `withGlobalTauri` gets `window.__TAURI__.log` from Tauri's own
  `api-iife.js`, which the gem ships

[Unreleased]: https://github.com/setdef/Tokra/commits/trunk/plugins/log
