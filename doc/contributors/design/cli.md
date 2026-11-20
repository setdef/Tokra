<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# The Tokra CLI

This document says what the `tokra` command does: where it lives, how it
finds a project, how it runs hooks, and what `tokra dev` and `tokra
build` do with each of tauri-cli's flags. It is for Tokra's
contributors, and nothing in it is built yet. Why things are so is in
ADR 015 (the CLI, and packaging through Fledge) and ADR 016 (development
unless `tokra build` made it). What `tokra build` hands Fledge is in
[packaging.md](packaging.md).

Tauri citations are to `vendor/tauri` at `9f0306fbc`, under
`crates/tauri-cli/src/` unless they name another crate.

## The gem

`tokra-cli` is a gem of its own, in `cli/` beside `plugins/`, with one
executable, `tokra`. An app's `Gemfile` puts it in the `development`
group, beside Fledge. It depends on `tokra` at the same version. Its
classes live under `Tokra::Cli`, one file per tauri-cli module it ports:
`dev`, `build`, `helpers/app_paths`, `helpers/config`, and
`helpers/mod`'s `run_hook`. It carries the built-in dev server and the
file watcher; the plan that builds them picks their libraries.

`tokra dev` and `tokra build` come first. tauri-cli's other commands
(`init`, `bundle`, `info`, `add`, `remove`, `plugin`, `icon`, `signer`,
`completions`, `permission`, `capability`, `inspect`, `migrate`) each
wait for a plan of their own; `android` and `ios` stay out with mobile.
The global `-v`/`--verbose`, `--help`, and `--version` are ported
(`lib.rs:131-171`).

## Finding the project

Both commands find the project as `app_paths` does
(`helpers/app_paths.rs:93-175`). The config's folder is the current one,
or its `src-tokra/`, when either holds a config file, else the first
found three levels down. The frontend's folder is the nearest with a
`package.json`, else the config folder's parent.

`TAURI_APP_PATH`, `TAURI_FRONTEND_PATH`, and `TAURI_CLI_CONFIG_DEPTH`
become `TOKRA_APP_PATH`, `TOKRA_FRONTEND_PATH`, and
`TOKRA_CLI_CONFIG_DEPTH` by the renaming rule of [config.md](config.md),
"File names": they are the developer's
instructions to the framework's own tool, and nothing outside Tokra reads
them. They steer that tool, not the app, so ADR 011 does not reach them.

The app's entry is the program Fledge would build: the project root's
gemspec executable, else its `main.rb`.

## Hooks

Hooks run as `run_hook` runs them (`helpers/mod.rs:71-127`): through
`sh -c` or `cmd /S /C`, in the frontend's folder or the hook's `cwd`,
failing with "{name} `{script}` failed with exit code {code}".

Their environment gets `command_env` and the interface's variables
(`helpers/mod.rs:35-48`, `interface/rust.rs:290-321`) under Tauri's own
names: `TAURI_ENV_PLATFORM_VERSION`, `TAURI_ENV_DEBUG`,
`TAURI_ENV_TARGET_TRIPLE`, `TAURI_ENV_ARCH`, `TAURI_ENV_PLATFORM`, and
`TAURI_ENV_FAMILY`. These are a contract with the frontend's tooling,
not the framework's brand: a Vite config from Tauri's templates reads
`TAURI_ENV_DEBUG` and `TAURI_ENV_PLATFORM` to pick its target and
minification. [config.md](config.md), "File names", keeps such names as
Tauri spells them, as it
keeps `__TAURI_INTERNALS__` (ADR 009) and `@tauri-apps/api` (ADR 010);
`TOKRA_ENV_*` would break that tooling. The triple is the host's as Rust
names it, since Fledge builds only for the host.

## tokra dev

It does what `dev::setup` does (`dev.rs:136-322`):

1. Runs `beforeDevCommand`, in the background, or to completion with
   `wait`, and kills its process tree when the app exits for good or on
   Ctrl-C.
2. Starts the built-in server on `frontendDist` when there is no
   `devUrl`. The server binds 127.0.0.1 from port 1430 up, or exactly
   `--port` (`dev/builtin_dev_server.rs:32-52`), and reloads the page
   when a file changes.
3. Waits for the dev server.
4. Writes the dev session, then runs the entry with Ruby from the
   config's folder.

With watching on, a change under the config's folder or an additional
watch folder restarts the app, as a Rust change rebuilds and reruns a
Tauri app. `.tokraignore` stands in for `.taurignore` by the rule for the
framework's own file names in [config.md](config.md), and Tauri's
`tauri-dev-watcher.gitignore` is ported as it is. An app in development
reads `bundle.resources` and `bundle.externalBin` where they are.

| tauri-cli flag | Tokra |
|---|---|
| `-r`, `--runner` and `build.runner` | translated: the command that runs the entry instead of `ruby` |
| `-t`, `--target` | deferred: Tokra runs on the host only |
| `-f`, `--features` and `build.features` | not ported: Tokra has no Cargo features to choose (ADR 011) |
| `-e`, `--exit-on-panic` | translated: an app that exits with a nonzero status ends `tokra dev` instead of waiting for a change (`dev.rs:324-332`) |
| `-c`, `--config` | ported, through the dev session |
| `--release` | not ported: there is no compile profile |
| `-- [runner args] -- [app args]` | ported: Ruby's arguments, then the app's `ARGV` |
| `--no-dev-server-wait`, `TAURI_CLI_NO_DEV_SERVER_WAIT` | ported; the variable is `TOKRA_CLI_NO_DEV_SERVER_WAIT`. The wait keeps Tauri's 90 tries, 2 s apart, and its messages (`dev.rs:268-313`) |
| `--no-watch`, `--additional-watch-folders` and `build.additionalWatchFolders` | ported |
| `--no-dev-server`, `--port`, `TAURI_CLI_PORT` | ported; the variable is `TOKRA_CLI_PORT` |

## The dev session

`tokra dev` sets no flag, since development is the default (ADR 016). It
hands the app its `--config` patches and the built-in server's `devUrl`
in `.tokra/dev.json`, which holds the merged patch and the `tokra dev`
process's id. `generate_context` merges it over the config only when no
packaged context exists and the recorded id is `Process.ppid`. A stale
file left by a crash, or a plain `ruby main.rb`, then changes nothing.
Merging it changes no more than editing `tokra.conf.json` would, and no
environment variable carries it (ADR 014).

## tokra build

It runs `build::setup`'s checks and hook (`build.rs:140-260`), then
`bundle::bundle`'s hook (`bundle.rs:163-202`), then Fledge:

1. Reads the config with the platform file and every `--config` patch
   folded in by `merge_patches`, in which `null` keeps a key
   (`helpers/config.rs:176-184`, `:278-294`).
2. Refuses `com.tokra.dev` and an identifier with characters other than
   alphanumerics, `-`, and `.`, and warns on one ending in `.app`
   (`build.rs:160-186`).
3. Checks every `bundle` key against [packaging.md](packaging.md) for the
   installers this build produces, and refuses, naming each key that
   stops it, before any hook runs.
4. Runs `beforeBuildCommand`, then checks `frontendDist` as Tauri does:
   it exists, it is not a folder named `src-tokra`, and it holds no
   `node_modules` or `src-tokra` (`build.rs:188-248`).
5. Stages what Tauri's bundle carries into `.tokra/stage/`.
6. Writes the packaged context beside the staged config, and
   `fledge.yml` at the staged root.
7. Runs `beforeBundleCommand` when an installer is to be built, as
   `bundle.rs:189-200` runs it when a bundle is.
8. Runs `RbConfig.ruby Gem.bin_path("fledge", "fledge") build --out
   PROJECT/.tokra/bundle [--sign IDENTITY | --sign-command COMMAND]
   ENTRY` in the staged root, where `ENTRY` is the staged entry. It
   passes Fledge's standard error through, prints each path Fledge
   prints, and exits with Fledge's status.

| tauri-cli flag | Tokra |
|---|---|
| `-r`, `--runner` | deferred: it replaces the compiler, and nothing compiles the app |
| `-d`, `--debug` | translated: hooks get `TAURI_ENV_DEBUG`; what else it changes waits on plan 050's question 2 (devtools) |
| `-t`, `--target` | deferred: Fledge builds for the computer it runs on (Fledge ADR 010) |
| `-f`, `--features` | not ported (ADR 011) |
| `-b`, `--bundles` | translated into `installers` ([packaging.md](packaging.md)) |
| `--no-bundle` | translated: `installers: []`, so Fledge writes the archive alone, the counterpart of Tauri's bare binary |
| `-c`, `--config` | ported, into the packaged context |
| `-- [args]` | deferred with `--runner` |
| `--ci`, `CI` | ported; `tokra build` asks nothing yet |
| `--skip-stapling` | waits with notarization: Fledge's `--notarize` always staples ([packaging.md](packaging.md), "macOS") |
| `--ignore-version-mismatches` | deferred: the npm and Cargo package check (`info::plugins::check_mismatched_packages`) waits for `tokra info` |
| `--no-sign` | ported: `--sign` and `--sign-command` are left off |

## Tests

They cover argument parsing; the config merge; the identifier and
`frontendDist` checks; hooks run through a real `sh -c` or `cmd /S /C`,
with the `TAURI_ENV_*` variables; the dev-server wait against a real
local socket; the built-in server over real HTTP; and `generate_context`
with and without a dev session, a stale session included. A test app
under `test/fixtures/` prints its `Tokra.is_dev` and `devUrl` without
opening a window, so `tokra dev` runs it in the core tests.
[packaging.md](packaging.md), "Tests", covers `tokra build`'s side.
