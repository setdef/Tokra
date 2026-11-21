<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Plugins

This document says how Tokra's plugins are built and shipped: the
plugin API, how a plugin answers Tauri's JavaScript packages, which of
Tauri's plugins Tokra ports, how a plugin builds on a Ferro gem, where
state shared across Ractors lives, and how the plugin gems are versioned
and released. It is for Tokra's contributors. Each plugin's README
covers its install, usage, and differences from Tauri.

## The plugin API

A plugin is a `Tokra::Plugin`, Tauri's `Plugin` trait as a Ruby class
with the same hooks: `name`, `initialize_plugin(app, config)`,
`initialization_script` and `initialization_script_2`,
`window_created`, `webview_created`, `on_navigation` (not yet called),
`on_page_load`, `on_event`, `extend_api`, and `drop`. Tauri's
`Plugin::initialize` is `initialize_plugin`, because Ruby's `initialize`
is the constructor and a plugin is made before the app exists (plan
064, decision 1). Most plugins are no subclass of their own: as in
Tauri, `Tokra::Plugin::Builder` makes a `Tokra::Plugin::TauriPlugin`
from blocks, and a first-party plugin's `init`, or its builder's
`build`, returns one. A plugin
that needs no native code is pure Ruby, where every Tauri plugin is
Rust.

An app registers a plugin with `Builder#plugin`, before the app is
built, or with `AppHandle#plugin` once it exists. Either way the plugin
is initialized with the app and its slice of `config.plugins`, the JSON
under its name or `nil`, as Tauri's plugin store hands it
(`crates/tauri/src/plugin.rs:999-1010`): `AppHandle#plugin` at once, and
`Builder#plugin`'s plugins in `App#run`, before the windows the config
lists. A plugin made with `Plugin::Builder` reads its slice with the
builder's `config:` type, `()` unless it names one, so a non-null slice
for a plugin that takes no config fails the app with Tauri's
"Error deserializing 'plugins.{name}' within your Tokra configuration";
a failed initialization raises `Error::PluginInitialization`. The core
plugins keep their older form, a subclass made with the app's handle.

With `withGlobalTauri`, each plugin gem's `api-iife.js` puts its API on
`window.__TAURI__`, as each Tauri plugin's does. A gem names its script
with `Tokra::Utils::Plugin.define_global_api_script_path` when it is
required, where a Tauri plugin's build script names it when the app
compiles, and `Tokra.generate_context` reads every named script
([ipc.md](ipc.md), "withGlobalTauri").

A plugin keeps its state apart from itself, as Tauri's does: it creates
the state and hands it to `manage`, and anyone with a manager reaches it
by class with `state`, which raises `KeyError` where Tauri panics, or
`try_state`, which answers `nil`. A plugin adds convenience methods to
every manager, as Tauri's extension traits do, by including a module
into `Tokra::Manager` when it is required: `tokra-clipboard` includes
`ClipboardManagerExt`, so `handle.clipboard` answers the managed
clipboard.

The first-party plugins live in this repository, one gem per folder
under `plugins/`, beside `tokra`, rather than in a repository of their
own or one each: changes that cross plugins are one commit, and there is
one CI workflow and no repository to go stale, as a separate devtools
repository did in the ratatui_ruby ecosystem. This was decided on
2026-01-31.

## Matching Tauri's JavaScript packages

A page uses Tauri's own npm packages against Tokra (ADR 008). For a
Tokra plugin to answer a Tauri package, it:

1. **Matches the IPC command names exactly.** The page invokes
   `plugin:clipboard-manager|read_text`; the plugin store routes on the
   plugin's name, and the plugin's `extend_api` sees the bare command:

   ```ruby
   def extend_api(invoke)
     case invoke.command
     when "read_text"
       invoke.resolve(read_text)
       true
     # ...
     end
   end
   ```

2. **Matches the payload and response formats.** It reads
   `invoke.payload` as Tauri does, a JSON value, and answers through
   `invoke.resolve` or `invoke.reject` in Tauri's format, with Tauri's
   error messages.
3. **Uses Tauri's plugin name,** such as `"clipboard-manager"`, which is
   also the key of its configuration.

To check a plugin against its package, read the Tauri plugin's
`guest-js/index.ts` for the command names and `src/commands.rs` for the
payload and response types, and dispatch the same commands in
`extend_api`.

| Tokra plugin | Tauri npm package |
|---|---|
| `tokra-clipboard` | `@tauri-apps/plugin-clipboard-manager` |
| `tokra-dialog` | `@tauri-apps/plugin-dialog` |
| `tokra-notification` | `@tauri-apps/plugin-notification` |
| `tokra-global-shortcut` | `@tauri-apps/plugin-global-shortcut` |
| `tokra-log` | `@tauri-apps/plugin-log` |
| `tokra-shell` | `@tauri-apps/plugin-shell` |
| `tokra-fs` | `@tauri-apps/plugin-fs` |
| `tokra-http` | `@tauri-apps/plugin-http` |
| `tokra-os` | `@tauri-apps/plugin-os` |
| `tokra-process` | `@tauri-apps/plugin-process` |
| `tokra-updater` | `@tauri-apps/plugin-updater` |

Of these, `tokra-clipboard`, `tokra-dialog`, `tokra-notification`,
`tokra-global-shortcut`, `tokra-log`, and `tokra-process` exist today.
Each names its Tauri package in its README, which tells the app
developer to use that package unchanged. Where a Tokra
plugin ever diverges from Tauri's API, its README says so.

## Which plugins Tokra ports

Tokra ports every official Tauri plugin that has a desktop side, with
Tauri's commands, payloads, and file formats, `fs`, `http`, and `store`
included. A plugin has two callers, the app's Ruby and the page, and
Ruby's `File` and `Net::HTTP` serve only the first: a page that calls
`@tauri-apps/plugin-fs` or `@tauri-apps/plugin-http` fails without a
plugin to answer it. Where a plugin writes a file, it writes Tauri's
format, so a `store` reads the JSON files Tauri's `store` wrote
(`plugins/store/src/lib.rs` in `tauri-apps/plugins-workspace` at
`d4613ff0`), and an app can move between Tauri and Tokra and keep them.
A plugin with no desktop side is out of scope with the rest of mobile.
This follows from ADR 008, and was recorded on 2026-11-13 by an agent
applying AGENTS.md's goals, with the maintainer accountable.

`fs` and `http` are large, and both need Tauri's scopes, which wait on
the access-control port ([config.md](config.md), "Access control"). No
plan has ported `fs`, `http`, or `store` yet. Each plugin's plan
enumerates the upstream plugin's commands and formats, and its tests
drive them through the IPC as the page does.

## Plugins over Ferro

A plugin that needs a Rust crate builds on the Ferro gem that binds it,
and carries no Rust of its own (ADR 020): `tokra-clipboard` over
`ferro-arboard`, `tokra-dialog` over `ferro-rfd`, `tokra-global-shortcut`
over `ferro-global-hotkey`, `tokra-log` over `ferro-time`, and
`tokra-notification` over `ferro-notify-rust`, `ferro-url`, and
`ferro-time`. The plugin maps
Tauri's commands, payloads, and error messages onto the Ferro gem's API.
Each fix goes to the layer it belongs to: `ferro-arboard` refuses an
image arboard would panic on, raising the crate's `ConversionFailure`,
and `tokra-clipboard` validates Tauri's payloads and turns
`Ferro::Arboard::Error` subclasses into `clipboard-manager`'s messages.
A third-party plugin that wraps a crate builds on a Ferro gem, or
contributes one to Ferro, rather than shipping its own extension.
Ferro binds crates that add something Ruby lacks, and skips crates that
duplicate the standard library or a popular gem, such as `serde_json`.

Tokra depends only on released Ferro versions: a published gem, or a
release tag pushed to Ferro's repository and named as a git source,
never a path source or an unpushed commit, since a Tokra contributor
clones Tokra alone. While a Ferro gem is not on RubyGems.org, each
Gemfile that needs it names its tag, with a `glob` that names only that
gem's folder. A Tokra change that needs a Ferro API waits for that
release.

## State shared across Ractors

A plugin whose state must be reached from more than one Ractor cannot
guard it with Ruby's `Mutex`, which no Ractor can share
(`Ractor.make_shareable(Mutex.new)` raises `Ractor::Error`), and
`Ractor.make_shareable` freezes what it shares. So the mutable state
lives in native code that guards it with Rust's `Mutex<T>`, behind a
`TypedData` marked `frozen_shareable`: frozen, and so shareable, but
mutable through the `Mutex`. Since plugins carry no Rust, that code is
the Ferro gem's:

| State | Where it lives |
|---|---|
| None (each call stands alone) | the plugin's Ruby over its binding |
| One copy per Ractor | a Ruby instance per Ractor |
| One copy shared across Ractors | the binding's `Mutex<T>` behind a `frozen_shareable` `TypedData` |

A Ferro gem marks its extension Ractor-safe only where the crate's types
allow calls from any thread, and freezes and shares objects only where
they are `Sync`. Where a Ferro object lives is the plugin's call:
`tokra-clipboard` builds its `Clipboard` frozen and Ractor-shareable,
holding a frozen `Ferro::Arboard::Clipboard` that takes calls from any
thread or Ractor, and marks itself retired with a `Ractor::Port`, which
is shareable yet closable once, since a frozen object cannot flip a
flag. Marking an extension Ractor-safe and a type `frozen_shareable` is
an assertion the binding's author makes, and a bug there breaks Ractor
safety.

## Versions and releases

The repository holds several gems: `tokra` at the root, and one plugin
gem for each folder under `plugins/`. Each gem keeps its own version in
its own `version.rb`, its own `CHANGELOG.md`, and its own tags, named
for the gem (`tokra-dialog/v0.1.0`), so a tag, a changelog section, and
a RubyGems version each name one gem's release, and a plugin fix ships
without a tokra release. A plugin bounds tokra by minor version
(`~> 0.0` today); a tokra release that moves its minor version raises every
plugin's bound to that minor in the same commit, since each plugin is
tested only against the tokra beside it. Releases run through the rake
tasks AGENTS.md's "Committing" section names, which the maintainer runs;
Bundler's `gem_tasks` are not loaded, since their `v0.1.0` tags would
collide between gems. Ferro releases its gems the same way.

The cost is that a tokra minor release changes every plugin's gemspec,
and each plugin then needs a release of its own before its users can
take the new tokra, and that an app's Gemfile can combine a plugin and a
tokra that were never tested together, within the bound. This was
decided on 2026-11-13 by an agent, with the maintainer accountable,
after the repository had worked this way since the first plugins; a
shared version for every gem, which Tauri's own plugins do not use
either, was weighed against it then.

`test/tasks/test_tokra_gems.rb` checks the list of gems against the
repository: every gemspec is listed, each version file matches its
gemspec, each plugin bounds tokra, and no Rakefile loads Bundler's
`gem_tasks`. `test/tasks/test_bump.rb` and `test/tasks/test_release.rb`
pin the tasks.
