<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Changelog

All notable changes to tokra-notification will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `tokra-notification` gem: `Tokra::Plugins::Notification::Plugin.new(app)`
  manages a `Tokra::Plugins::Notification::Notification` (reachable as
  `app.notification`) with Tauri's `NotificationBuilder`, serves Tauri's
  desktop notification commands (`notify`, `request_permission`,
  `is_permission_granted`) for `@tauri-apps/plugin-notification` with
  Tauri's argument errors, and backs the page's `window.Notification`;
  permission is always granted, a notification shows its title (or the
  product name), body, icon, and sound, and goes out on its own thread;
  macOS names the app by its identifier, Windows names none; an
  `Attachment` holds its URL as a `Ferro::Url::Url`, and `Schedule::At`
  its date as a `Ferro::Time::OffsetDateTime`; it is pure Ruby and
  depends on `ferro-notify-rust` 0.1.0 (notify-rust 4.18.2),
  `ferro-url` 0.1.0 (url 2.5.8), and `ferro-time` 0.1.0 (time
  0.3.55), which apps take from their git tags until they are on
  RubyGems.org

[Unreleased]: https://github.com/setdef/Tokra/commits/trunk/plugins/notification
