<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Tokra Rails + SQLite Verification App

A minimal Rails 8.1 to-do application demonstrating Tokra's custom protocol
integration with a full-stack Rails app using SQLite.

## Purpose

This example verifies that:
1. Rails can run inside Tokra via `Rack::Handler::Tokra`
2. SQLite database works correctly with the Ractor model
3. Turbo/Hotwire updates work through the custom protocol
4. Form submissions and redirects function properly

## Running

```bash
cd examples/verify_rails_sqlite
bin/rails db:migrate
bin/rails server
```

Then open http://localhost:3000 in your browser.

## Design

Uses the **Refined Paper** aesthetic:
- Warm cream/umber palette with OKLCH color functions
- Crimson Pro serif for display typography
- Source Sans 3 for body text
- Full dark mode support via `prefers-color-scheme`
- Editorial, asymmetric layout

## Architecture

See [ADR 002](../../doc/contributors/adr/002.md) for the Tokra Rails architecture.
