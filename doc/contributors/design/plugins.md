<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Plugins

This document says how Tokra's plugins are built and shipped. It is for
Tokra's contributors. Each plugin's README covers its install, usage,
and differences from Tauri.

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
applying AGENTS.md's design precedence, with the maintainer accountable.

`fs` and `http` are large, and both need Tauri's scopes, which wait on
the access-control port ([config.md](config.md), "Access control"). No
plan has ported `fs`, `http`, or `store` yet. Each plugin's plan
enumerates the upstream plugin's commands and formats, and its tests
drive them through the IPC as the page does.

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
