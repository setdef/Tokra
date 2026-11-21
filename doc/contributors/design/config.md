<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# The Config and the Context

This document says how a Tokra app reads its config and builds its
`Context`: what stands in for Tauri's `generate_context!`, which files it
reads and where it looks, what the schema is, and what the Ruby surface
looks like. It is for Tokra's contributors. Why the config is read when
the app starts is ADR 014. The README's "The config file" tells app
developers how to write one.

Tauri citations are to `vendor/tauri` at `9f0306fbc`.

## The loader

`Tokra.generate_context(path = nil)` is Tauri's `generate_context!`,
translated from a macro that runs when the app compiles into a method
that reads the files when it is called. It returns a `Tokra::Context`
for `Builder#build` or `Builder#run`.

| Tauri, at compile time | Tokra, at start |
|---|---|
| `tauri::generate_context!()` | `Tokra.generate_context` |
| `tauri::generate_context!("path")` | `Tokra.generate_context("path")` |
| A relative path joins `CARGO_MANIFEST_DIR` | A relative path joins the entry script's directory ("Where the loader looks") |
| A compile error | An exception, raised before any window exists, with the same message |
| Icons and assets embedded with `include_bytes!` | Read and decoded when the method runs |
| `TAURI_CONFIG` merged over the file | Not read ("No environment variable") |
| `root` argument (the `tauri` crate path) | None: Ruby has no crate paths |
| `capabilities`, `assets`, `test` arguments | Each with the plan that ports what it feeds |

Tokra keeps the split between the three crates the macro spans, so each
part answers to one source: `Tokra.generate_context` is the macro
(`crates/tauri-macros/src/lib.rs:76-87`, `src/context.rs:24-169`),
`Tokra::Codegen` is tauri-codegen's `get_config` and `context_codegen`
(`crates/tauri-codegen/src/lib.rs:53-99`, `src/context.rs:135-491`), and
`Tokra::Utils::Config` is tauri-utils' schema and its `parse` module
(`crates/tauri-utils/src/config/parse.rs`).

The context's `dev` is `true` until the packaged context lands
([packaging.md](packaging.md), "The packaged context").

## File names

Tokra renames Tauri's brand strings where they name the framework: the
`tokra://` scheme, the "Tokra App" default title, the "Tokra Window"
class on Windows. The config files follow:

| Tauri | Tokra |
|---|---|
| `tauri.conf.json` | `tokra.conf.json` |
| `tauri.conf.json5` | `tokra.conf.json5` |
| `Tauri.toml` | `Tokra.toml` |
| `tauri.<platform>.conf.json`, `.json5` | `tokra.<platform>.conf.json`, `.json5` |
| `Tauri.<platform>.toml` | `Tokra.<platform>.toml` |

`<platform>` is `macos`, `windows`, or `linux`, Tauri's desktop names
(`parse.rs:51-75`). The platform file is merged over the main one as
Tauri merges it, with JSON Merge Patch (RFC 7396, json-patch 3.0.1's
`merge`): an object merges key by key, `null` deletes a key, and
anything else, an array included, replaces what was there
(`parse.rs:180-188`).

Error messages that name the framework's config file rename it the same
way: Tauri's "unable to parse JSON Tauri config file at {path} because
{error}" reads "unable to parse JSON Tokra config file at {path} because
{error}", and "`tauri.conf.json > version` must be a semver string"
names `tokra.conf.json`. Every other word stays Tauri's. Names Tauri's
frontend tooling reads, such as `TAURI_ENV_*`, `__TAURI_INTERNALS__`,
and `@tauri-apps/api`, are not the framework's brand but its contract
with the page, and keep Tauri's spelling.

## The schema

`Tokra::Context` is Tauri's `Context` (`crates/tauri/src/lib.rs:349-527`),
field for field where Ruby gives the field a meaning, and
`Tokra::Config` (`Tokra::Utils::Config::Config`) is Tauri's `Config`
(`crates/tauri-utils/src/config.rs:3267-3332`), with Tauri's
sub-structures. Inline capabilities are the exception: Tokra keeps each
as its JSON until the capabilities port types it, and nothing acts on
them before then.

Every key, alias, default, and refusal is Tauri's: camelCase keys with
their kebab-case aliases, `deny_unknown_fields` on every struct that has
it, `identifier` required, `app.windows` defaulting to none, and serde's
error texts for a missing field, an unknown one, or a value of the wrong
type. So Tauri's configuration reference and its JSON schema
(`crates/tauri-schema-generator/schemas/config.schema.json`) describe a
Tokra config too, and `"$schema"` may name Tauri's. Fields that drive
something Tokra does not have yet, such as the bundler's, are read and
checked but not acted on; plan 054's inventory says which.

The window config's default title is Tauri's "Tauri App"
(`config.rs:2061-2063`, and `tauri-runtime-wry/src/lib.rs:827`), renamed
to "Tokra App", in the config and in `WindowBuilder` alike.

## Where the loader looks

`CARGO_MANIFEST_DIR` is the directory holding the app's `Cargo.toml`,
which in a Tauri app is `src-tauri/`, beside `tauri.conf.json`. A Ruby
app has no manifest; the file that plays its part is the script Ruby was
started with, so the anchor is that script's directory. Tokra records it
when `tokra` is required, so a later `Dir.chdir` does not move it:
`File.dirname(File.realpath($PROGRAM_NAME))` when `$PROGRAM_NAME` names a
file, resolving a symlinked launcher to the script beside the config,
and the working directory otherwise (as for `ruby -e` or IRB).

With no argument the loader reads `<anchor>/tokra.conf.json` (or
`tokra.conf.json5`). If none exists it raises Tauri's `Io` error,
"unable to read Tokra config file at {path} because entity not found",
since the macro checks only a path it was given
(`tauri-macros/src/context.rs:126-133`; `parse.rs:327-333`). With an
argument it works as the macro's argument does: a relative path joins
the anchor, an absolute path is taken as given, and a path where no
supported file exists raises the macro's "no file at path {path} exists,
expected tokra config file". That check looks for the supported names in
the path's directory, the platform names if the path names a platform
file and the main names otherwise (`parse.rs:206-225`). Once it passes,
only the directory matters: the loader reads that directory's
`tokra.conf.json` and its platform file
(`tauri-codegen/src/lib.rs:57-81`).

The anchor is the entry script, not the file that calls
`generate_context`. For an app the two agree. A library that called it
with no argument would read the app's config, where a Rust library crate
calling the macro reads its own; nothing in Tokra does that. Under a
launcher that is not a symlink, such as a binstub in `bin/`, the entry
script is the launcher, so the app passes a path.

`Rack::Handler::Tokra.run` anchors at `config.ru`'s directory when
rackup hands it the `:config` option (rackup 2.3.1
`lib/rackup/server.rb:341`). The `rackup` command expands that path
(`:404`), but `bin/rails server` passes `"config.ru"` as written
(railties 8.1.2 `server_command.rb:110`, `:161`), so the handler expands
a relative path against the working directory, as rackup would.

## No environment variable

`tauri dev --config` and `tauri build --config` merge their patches into
`TAURI_CONFIG` (`crates/tauri-cli/src/helpers/config.rs:176-184`), and
codegen reads that variable while it compiles
(`tauri-codegen/src/lib.rs:83-87`). It shapes the binary the developer
ships; the person who runs the binary cannot change it. Tokra reads its
config when the app starts, so reading a variable then would hand the
app's configuration, its security settings included, to whoever starts
the process. `Tokra.generate_context` reads no environment variable. The
`--config` merge belongs to the CLI ([cli.md](cli.md)).

## Formats

Tauri gates JSON5 and TOML behind the `config-json5` and `config-toml`
Cargo features (`parse.rs:21-28`). Both add behavior and relax no
default, so by AGENTS.md's rule for Cargo features Tokra builds both in.
JSON5 is: Tokra reads `tokra.conf.json5`, and tries a `tokra.conf.json`
as JSON5 first, reporting serde_json's error if both fail, as Tauri does
with the feature on (`parse.rs:281-302`). TOML is not yet: `Tokra.toml`
raises `ConfigError::DisabledFormat`, as Tauri without its feature does,
until the maintainer answers whether tomlrb's differences from Tauri's
toml crate are acceptable. Plan 054 records what Tokra's JSON5 parser
reproduces of Tauri's json5 0.4.1.

## The Ruby surface

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: MIT-0
-->
```ruby
# <entry script's directory>/tokra.conf.json, with tokra.macos.conf.json
# (on macOS) merged over it.
context = Tokra.generate_context

# A relative path joins the entry script's directory; an absolute one is
# taken as given.
context = Tokra.generate_context("src-tokra/tokra.conf.json")

Tokra::Builder.default
  .setup { |app| puts app.config.identifier }
  .run(context)

app = Tokra::Builder.default.build(context)
app.run { |handle, event| }

context.config           #=> Tokra::Config (Tokra::Utils::Config::Config)
context.config.plugins["log"]  #=> {"level" => "info"}: String keys, JSON values
context.config = context.config.with(identifier: "com.example.beta")
context.package_info     #=> Tokra::PackageInfo: name, version, authors, description, crate_name
context.pattern          #=> Tokra::Pattern::Brownfield

app.config.app.windows   #=> [Tokra::Utils::Config::WindowConfig, ...]
app.package_info.version #=> "1.2.0"
Tokra::WebviewWindowBuilder.from_config(app, app.config.app.windows[0]).build
```
<!-- SPDX-SnippetEnd -->

`config.plugins` holds each plugin's JSON as Tauri's `JsonValue` holds
it, with String keys. A plugin still takes a config Hash in its
constructor and may be given one in code, until the plan that ports
`Builder#plugin` hands each plugin its slice of `config.plugins` as
Tauri's builder does.

`Context#config=` and `#package_info=` translate Tauri's `config_mut`
and `package_info_mut`: Ruby has no mutable borrow, and the values are
frozen, so a caller builds a changed copy with `Data#with` and stores
it. `#set_default_window_icon` and `#set_tray_icon` translate the icon
setters the same way.

## Access control

Not built yet; plan 062 ports it. Tauri decides which page may call
which command with capabilities, permissions, and scopes, and does most
of that work before the app runs: a plugin's build script generates its
permission files, the app's build script finds every plugin's files
through Cargo's `links` key and reads the app's `capabilities/` folder
(`crates/tauri-build/src/acl.rs`), and `generate_context!` resolves the
result into the authority the app starts with
(`crates/tauri-codegen/src/context.rs`). At run time every `plugin:`
command is refused unless a capability grants it, from the app's own
pages too (`crates/tauri/src/webview/mod.rs:1801-1831`).

In Tokra that work runs in `Tokra.generate_context`, at start, so its
`Context` arrives resolved, as Tauri's does, and a broken capability
raises before any window opens. Gem metadata stands in for the `links`
key: each plugin gem names its manifest key and permission folder in its
gemspec, read from the gems RubyGems activated, so every plugin gem the
app depends on contributes its permissions, registered or not, as in
Tauri. This was decided on 2026-11-13 for plan 062, from AGENTS.md's
design precedence, with the maintainer accountable. Resolving in
`Builder#build` would leave the `Context` without an authority and give
a plugin added in `setup` no manifest; a rake or CLI task that writes a
resolved file is a build step, and stays open only as the form a
packaged app may carry.

- An app's `capabilities/` and `permissions/` folders sit beside its
  config file, where every Tauri project keeps them.
- A plugin gem commits and packages its permission files, generated by
  a rake task, as Tauri's plugins commit theirs. The core plugins'
  permissions are built in memory from Tauri's table
  (`crates/tauri/build.rs:16-225`), since Tauri commits none of those.
- A plugin mirrors its Tauri original's permission files exactly, the
  ones for commands Tokra does not implement included, so a capability
  written for Tauri validates.
- A plugin whose gem leaves the metadata out contributes nothing, and
  its commands are refused.
- The check turns on in one commit, which also gives every example,
  fixture, and test the capabilities it needs. Before that commit the
  authority is resolved and held, and checks nothing. From it on, an app
  needs a capability to call any plugin command, as in Tauri. Until then
  the local-origin stopgap stands ([ipc.md](ipc.md), "Only the app's
  own origin may invoke").
- A refusal carries Tauri's debug text in development and its release
  text in a packaged app.
- Tauri's behavior is ported as written where it surprises: a deny in
  any capability refuses that command everywhere
  (`crates/tauri/src/ipc/authority.rs:446-452`), a remote page may call
  app commands when the app defines no app permissions
  (`webview/mod.rs:1802`), and `add_capability` numbers a runtime
  capability's scopes from 1 again (`authority.rs:198-223`).
- tauri-build's `Attributes` (a capabilities path pattern, an app
  manifest of commands, inlined plugins) are not ported yet. A plugin
  that is not a gem has no permissions until they are.

Resolving on every start has not been measured.
