<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Rails Desktop App Example

Runs an ordinary Rails app in a native desktop window.

You already know how to build with Rails. Shipping that app to someone's
desktop usually means a different stack: Electron, a bundled browser, or
a local server on a port that other programs can reach. Tokra lets you
keep Rails. This example is a stock Rails 8.1 to-do app (SQLite, Turbo,
import maps, a scaffolded `Todo`) that runs in a Tokra window, with no
web server and no open port.

## What Changes

One new file, [`tokra.rb`](tokra.rb), starts the app in place of
`bin/rails server`. Trimmed to its core:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long
  SPDX-License-Identifier: MIT-0
-->
```ruby
require "tokra"

ENV["RAILS_ENV"] = "production"
require_relative "config/environment"

Rack::Handler::Tokra.run(Rails.application, title: "Tokra Tasks", width: 900.0, height: 700.0)
```
<!-- SPDX-SnippetEnd -->

`Rack::Handler::Tokra` takes Puma's place. The window asks for
`tokra://localhost/...`, and the handler passes each request to your
Rack app and the response back to the window.

Three settings change:

- **`config.hosts.clear`** in
  [`config/environments/production.rb`](config/environments/production.rb).
  Nothing outside the window can reach the app, so host checks guard
  nothing.
- **`config.public_file_server.enabled = true`** in the same file. No
  web server sits in front of Rails, so Rails serves `public/` and your
  assets itself.
- **`skip_forgery_protection`** in
  [`ApplicationController`](app/controllers/application_controller.rb).
  No other site can send a request to a `tokra://` URL.

Everything else is what `rails new` and `rails generate scaffold` gave
you: models, controllers, views, migrations, Turbo, and Active Record on
SQLite. The files for deploying to a server (Kamal, Docker, Thruster)
are gone, because a desktop app has no server to deploy to.

## What Problems Does This Solve?

### "Do I have to rewrite my app for the desktop?"

No. Your routes, controllers, and views run unchanged. Forms submit,
redirects follow, cookies persist, and Turbo swaps pages, all through
the window's own protocol.

### "Does my app listen on a port?"

No. Requests never touch the network. Other programs on the machine
cannot reach your app, so you skip CSRF tokens and host checks.

### "Where does my data live?"

In SQLite, through Active Record, exactly as in any Rails app. This
example keeps its database in `storage/production.sqlite3`.

## Usage

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long
  SPDX-License-Identifier: MIT-0
-->
```bash
cd examples/verify_rails_sqlite
bundle install
export SECRET_KEY_BASE=$(bin/rails secret)
RAILS_ENV=production bin/rails db:prepare
bundle exec ruby tokra.rb
```
<!-- SPDX-SnippetEnd -->

- Click **Add task**, type a title, and save it.
- Tick a task's checkbox to finish it, or click **Edit** to change it.
- Close the window to quit.

## Learning Outcomes

Use this example if you want to:

- Turn an existing Rails app into a desktop app.
- See which Rails defaults matter when there is no web server.
- Start a new desktop app with the Rails tools you already know.

[ADR 002](../../doc/contributors/adr/002.md) explains how Tokra runs
Rails.

[Read the source code →](tokra.rb)
