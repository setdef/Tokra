<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Tokra

[![CI](https://github.com/setdef/Tokra/actions/workflows/ci.yml/badge.svg?branch=trunk)](https://github.com/setdef/Tokra/actions/workflows/ci.yml) [![Gem Version](https://img.shields.io/gem/v/tokra)](https://rubygems.org/gems/tokra) [![License](https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fraw.githubusercontent.com%2Fsetdef%2FTokra%2Ftrunk%2Ftokra.gemspec&search=spec%5C.license%20%3D%20%22(.*)%22&replace=%241&label=License&color=a2c93e)](https://spdx.org/licenses/AGPL-3.0-or-later.html) [![Ruby](https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fraw.githubusercontent.com%2Fsetdef%2FTokra%2Ftrunk%2Ftokra.gemspec&search=spec%5C.required_ruby_version%20%3D%20%22(.*)%22&replace=%241&label=Ruby&logo=ruby&color=a2c93e)](#compatibility) [![tao](https://img.shields.io/badge/dynamic/toml?url=https%3A%2F%2Fraw.githubusercontent.com%2Fsetdef%2FTokra%2Ftrunk%2Fext%2Ftokra%2FCargo.toml&query=%24.dependencies.tao&prefix=v&label=tao&color=a2c93e)](https://crates.io/crates/tao) [![wry](https://img.shields.io/badge/dynamic/toml?url=https%3A%2F%2Fraw.githubusercontent.com%2Fsetdef%2FTokra%2Ftrunk%2Fext%2Ftokra%2FCargo.toml&query=%24.dependencies.wry.version&prefix=v&label=wry&color=a2c93e)](https://crates.io/crates/wry) [![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20Windows%20%7C%20Linux-a2c93e)](#compatibility) [![Forum: Discussion](https://img.shields.io/badge/forum-discussion-5865F2.svg?logo=discourse)](https://forum.setdef.com/tags/c/tokra/discussion) [![Forum: Bug Reports](https://img.shields.io/badge/forum-bug_reports-4954d5.svg?logo=discourse)](https://forum.setdef.com/tags/c/tokra/bug) [![Forum: Announcements](https://img.shields.io/badge/forum-announcements-3b44ac.svg?logo=discourse)](https://forum.setdef.com/tags/c/tokra/announcement) [![Certified Shovelware](https://justin.searls.co/img/shovelware.svg)](https://justin.searls.co/shovelware/)

Tokra builds desktop apps with a Ruby backend and a web frontend. It is a
port of [Tauri](https://tauri.app) to Ruby: your Ruby code runs in the
app's process, and your HTML, CSS, and JavaScript run in the operating
system's web view.

A Ruby developer who wants a desktop app usually has to change stacks.
[Electron](https://www.electronjs.org) ships Chromium and Node.js inside
every app, and you write the backend in JavaScript. Tauri uses the
system's web view, and you write the backend in Rust.
[Glimmer DSL for LibUI](https://github.com/AndyObtiva/glimmer-dsl-libui)
keeps you in Ruby but draws native widgets, so you leave HTML behind.
Tokra keeps both Ruby and HTML. Your [Rack](https://github.com/rack/rack)
app, whether Rails, Roda, or a lambda, answers the window's requests for
`tokra://` URLs inside the process. No web server runs, and no port opens.
The page calls Ruby through Tauri's JavaScript API.

Tokra mirrors Tauri 2.9.5 class for class: its names, its config file, its
error messages, and its IPC wire format. The crates Tauri uses for
windows and web views, [tao](https://github.com/tauri-apps/tao) and
[wry](https://github.com/tauri-apps/wry), do the native work through a
Rust extension that compiles when you install Tokra. Everything else,
from the IPC router to the config reader, is Ruby.

## A first app

This app is two files: a config that describes one window, and a script
that serves a page and answers one command from it.

`tokra.conf.json`, beside the script:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long
  SPDX-License-Identifier: MIT-0
-->
```json
{
  "identifier": "com.example.hello",
  "productName": "Hello",
  "app": {
    "withGlobalTauri": true,
    "windows": [{ "title": "Hello", "width": 480, "height": 320 }]
  }
}
```
<!-- SPDX-SnippetEnd -->

`app.rb`:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long
  SPDX-License-Identifier: MIT-0
-->
```ruby
require "tokra"

PAGE = <<~HTML
  <h1>Hello from Tokra</h1>
  <button onclick="greet()">Greet</button>
  <p id="answer"></p>
  <script>
    async function greet() {
      const answer = await window.__TAURI__.core.invoke("greet", { name: "Ada" });
      document.getElementById("answer").textContent = answer;
    }
  </script>
HTML

site = ->(_env) { [200, { "content-type" => "text/html" }, [PAGE]] }

Rack::Handler::Tokra.run(
  site,
  invoke_handler: Ractor.shareable_proc { |invoke|
    next false unless invoke.command == "greet"

    invoke.resolve("Hello, #{invoke.payload["name"]}!")
    true
  }
)
```
<!-- SPDX-SnippetEnd -->

Run it with `bundle exec ruby app.rb`, after the steps in
[Installation](#installation). A 480 by 320 window titled "Hello" opens
and shows the page. Click **Greet**: the page sends the `greet` command
to Ruby, the handler answers, and "Hello, Ada!" appears under the button.
Close the window, and the process exits.

`Rack::Handler::Tokra.run` reads the config, opens each window its
`app.windows` lists, sends each request from those windows to `site`, and
runs until the last window closes. `withGlobalTauri` puts Tauri's
JavaScript API on `window.__TAURI__`, so a page without a bundler can
call it. The handler answers `true` for a command it took and `false`
for one it didn't, and the page's promise then rejects with
`Command NAME not found`.

## Compatibility

Tokra runs on macOS, Windows, and Linux. CI runs its tests on all three,
for every change, on GitHub's `macos-latest` (Apple silicon),
`windows-latest`, and `ubuntu-latest` runners.

| | macOS | Windows | Linux |
|---|---|---|---|
| Ruby | 4.0.1 or newer | 4.0.1 or newer, from [RubyInstaller](https://rubyinstaller.org) | 4.0.1 or newer |
| [Rust](https://www.rust-lang.org/tools/install) | 1.88 or newer; 1.99 or newer on macOS 27 | 1.88 or newer, GNU toolchain (`x86_64-pc-windows-gnu`) | 1.88 or newer |
| Web view | WKWebView | WebView2 | WebKitGTK 4.1, version 2.40 or newer |
| To build | the Xcode Command Line Tools | libclang and RubyInstaller's MSYS2 tools | `libwebkit2gtk-4.1-dev`, `libgtk-3-dev`, `libxdo-dev`, `libclang-dev`, `pkg-config` |
| To run | nothing more | the WebView2 runtime | `libxdo3` for menus; `libayatana-appindicator3-1` for tray icons |

The Linux package names are Debian's and Ubuntu's. On Arch, libxdo comes
with `xdotool` and the tray library is `libayatana-appindicator`. Without
an AppIndicator library, building a tray icon raises `Tokra::Error::Tray`.
RubyInstaller's Ruby is a MinGW build, and rb-sys refuses to compile it
with Rust's MSVC toolchain. The
[CI workflow](.github/workflows/ci.yml) shows a full Windows setup,
including where clang finds Ruby's headers.

Cargo builds exactly the Rust crate versions in Tokra's
`Cargo.lock` and fails rather than resolve newer ones. To build against
newer versions anyway, set `RB_SYS_EXTRA_CARGO_ARGS` (for example to an
empty string); it replaces `--locked`.

Tokra ports Tauri piece by piece. These parts of Tauri are not available
yet:

- **Capabilities.** Tokra has no permission system. Pages your app serves
  (`tokra://localhost`, or `http://tokra.localhost` on Windows) can call
  every command. Pages from any other origin are refused with
  `Command NAME not allowed by ACL`.
- **JavaScript APIs for windows, web views, the app, and paths.** From the
  page, Tauri's `core` (commands), `event`, `menu`, `tray`, and `image`
  APIs work. Control windows from Ruby.
- **`devUrl` and `frontendDist`.** Tokra reads both from the config, but
  loads pages only from a Rack app or a protocol you register, not from a
  dev server or a folder of built files.
- **TOML configs.** The config is JSON or JSON5.
- **The `tokra` command and app bundles.** See
  [Shipping your app](#shipping-your-app).
- **iOS and Android.** Tokra runs on desktop systems only.

## Installation

The `tokra` 0.0.1.pre.2 gem on RubyGems.org dates from January 2026 and
predates the API in this README. Until the next release, use a clone of
this repository. Install the build requirements from
[Compatibility](#compatibility) first.

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long
  SPDX-License-Identifier: MIT-0
-->
```sh
git clone --recurse-submodules https://github.com/setdef/Tokra.git
cd Tokra
bundle install
bundle exec rake compile
```
<!-- SPDX-SnippetEnd -->

`rake compile` builds the Rust extension and extracts Tauri's JavaScript
from the `vendor/tauri` submodule into `lib/tokra/js/`.

Then point your app's `Gemfile` at the clone; this one assumes the
clone sits beside your app's folder. Tokra reads URLs with
[ferro-url](https://github.com/setdef/Ferro), a Ruby binding of the Rust
`url` crate that Tauri uses. It is not on RubyGems.org yet, so take it
from its release tag:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long
  SPDX-License-Identifier: MIT-0
-->
```ruby
source "https://rubygems.org"

gem "tokra", path: "../Tokra"
gem "ferro-url", git: "https://github.com/setdef/Ferro",
  tag: "ferro-url/v0.1.0.pre.1", glob: "gems/url/*.gemspec"
```
<!-- SPDX-SnippetEnd -->

Run `bundle install` in your app's folder. Bundler compiles
ferro-url's Rust extension as it installs the gem.

## Usage

### The config file

`tokra.conf.json` is Tauri's `tauri.conf.json` under Tokra's name, with
the same keys, so
[Tauri's configuration reference](https://v2.tauri.app/reference/config/)
documents it. Every app needs one, and it needs an `identifier`, a
reverse domain name such as `com.example.notes`. Without one, Tokra
raises ``missing field `identifier` `` before any window opens.

Tokra looks for the file beside the script you run, even if the script
changes directory later. A `tokra.macos.conf.json`,
`tokra.windows.conf.json`, or `tokra.linux.conf.json` beside it is
merged over it on that platform.
If you prefer JSON5, with its comments and trailing commas, name the files
`tokra.conf.json5` and `tokra.macos.conf.json5` instead; Tokra reads them
the same way.
To keep the config elsewhere, pass its path:
`Tokra.generate_context("config/tokra.conf.json")`.

The config's `app.windows` lists the windows the app opens at start, with
any of Tauri's window keys (`title`, `width`, `height`, `resizable`,
`decorations`, and the rest). A config that lists no windows opens none.

### Rails and Roda

Pass `Rack::Handler::Tokra.run` any Rack app. For Rails, pass
`Rails.application`:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long
  SPDX-License-Identifier: MIT-0
-->
```ruby
ENV["RAILS_ENV"] = "production"
require_relative "config/environment"

Rack::Handler::Tokra.run(Rails.application)
```
<!-- SPDX-SnippetEnd -->

[examples/verify_rails_sqlite](examples/verify_rails_sqlite) is a stock
Rails 8.1 to-do app (SQLite, Turbo, import maps) that runs this way. Its
README lists the three settings a Rails app changes for the desktop and
how it keeps its `secret_key_base`.
[examples/verify_ping_pong](examples/verify_ping_pong) does the same
with a Roda app that submits a form, follows a redirect, and calls Ruby
from the page.

### More control: the Builder

`Rack::Handler::Tokra.run` builds a `Tokra::Builder` for you. Build one
yourself to add a setup hook, menus, tray icons, event listeners, or
plugins, as you would in a Tauri app's `main`. With `site` from the
first app:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long
  SPDX-License-Identifier: MIT-0
-->
```ruby
require "tokra"
require "tokra-dialog"

app = Tokra::Builder.default
  .app(site)
  .setup(&Ractor.shareable_proc { |app| puts "#{app.config.product_name} is running" })
  .build(Tokra.generate_context)
app.handle.plugin(Tokra::Plugins::Dialog::Plugin.new(app.handle))
app.run
```
<!-- SPDX-SnippetEnd -->

`Tokra.generate_context` reads the config, as Tauri's
`generate_context!()` does when a Tauri app compiles. `Builder#build`
makes the app from it, and `App#run` opens the config's windows, calls
the setup hook, and runs the event loop. `Builder#run(context)` does
both steps at once.

Wrap each block you give the Builder, and the `invoke_handler`, in
`Ractor.shareable_proc`. For a plain block, the Builder raises
`setup block must be Ractor-shareable (use Ractor.shareable_proc)`, and
`Ractor.shareable_proc` itself raises `Ractor::IsolationError` for a
block that refers to a mutable object outside it. Keep such objects in
managed state: `Builder#manage(object)`, then `app.state(ObjectClass)`.

`App#run` never returns. When the app exits, it raises `SystemExit` with
the exit code, so `ensure` clauses and `at_exit` hooks run, but code after
the call does not. Put shutdown work in a handler for
`Tokra::RunEvent::Exit`.

### Plugins

Each of Tauri's official plugins that Tokra ports is a separate gem,
in [plugins/](plugins). The ones with a frontend package serve Tauri's
commands, so the package works unchanged.

| Gem | Tauri plugin | Frontend package |
|---|---|---|
| [tokra-clipboard](plugins/clipboard/README.rdoc) | clipboard-manager | `@tauri-apps/plugin-clipboard-manager` |
| [tokra-dialog](plugins/dialog/README.rdoc) | dialog | `@tauri-apps/plugin-dialog` |
| [tokra-global-shortcut](plugins/global-shortcut/README.rdoc) | global-shortcut | `@tauri-apps/plugin-global-shortcut` |
| [tokra-log](plugins/log/README.rdoc) | log | none yet; Ruby only |
| [tokra-notification](plugins/notification/README.rdoc) | notification | `@tauri-apps/plugin-notification` |

The plugins are pure Ruby, but four of them build on
[Ferro](https://github.com/setdef/Ferro) gems that compile Rust
extensions and are not on RubyGems.org yet. Each plugin's README gives
the Gemfile lines for its Ferro gems. Keep each line's `glob` to that
gem's folder, as those READMEs show; with a wider glob, Bundler can take
other Ferro gems from the wrong tag. Use the plugins from your clone as
you use Tokra, with `path: "../Tokra/plugins/dialog"` and so on.

### Shipping your app

There is no `tokra` command yet, and packaging an app for people who
don't have Ruby is planned through [Fledge](https://github.com/setdef/Fledge).
Today you run a Tokra app with `bundle exec ruby`.

## Documentation

- **API reference.** In your clone, `bundle exec rake rdoc` writes it to
  `tmp/rdoc/index.html`. Most classes name the Tauri type they mirror.
- **[Tauri's configuration reference](https://v2.tauri.app/reference/config/)**
  documents every key of `tokra.conf.json`.
- **[Tauri's JavaScript API reference](https://v2.tauri.app/reference/javascript/api/)**
  documents what your page calls. See
  [Compatibility](#compatibility) for the parts Tokra serves.
- **[CHANGELOG.md](CHANGELOG.md)** lists the changes you can observe
  since the last release, with breaking ones marked.
- **[examples/](examples)** holds three apps: a static page served
  through Tokra's low-level native classes, a Roda app, and a Rails app.
- **The plugin READMEs**, linked under [Plugins](#plugins), cover each
  plugin's install, usage, and differences from Tauri.

## Reporting problems

Report a bug under
[Bug Reports](https://forum.setdef.com/tags/c/tokra/bug) on the setdef
forum or as a [GitHub issue](https://github.com/setdef/Tokra/issues), and
ask questions under
[Discussion](https://forum.setdef.com/tags/c/tokra/discussion). Include
your operating system and its version, the output of `ruby -v` and
`rustc -V`, the command you ran, and its full output.

## Contributing

Start with [AGENTS.md](AGENTS.md). It holds the rules for people and
agents alike, from where Tauri's source lives to the full check suite,
`bundle exec rake`, that every change passes. Everyone who takes part
follows the [code of conduct](CODE_OF_CONDUCT.md).

## License

Tokra and its plugins are licensed under the
[GNU Affero General Public License, version 3 or later](LICENSE). Code
adapted from Tauri keeps Tauri's license, Apache-2.0 OR MIT. The
documentation is CC-BY-SA-4.0. The code snippets in this README are
MIT-0, so you can copy them into your app under any license. Every file
names its license, the
[REUSE](https://reuse.software) tool checks it, and the texts are in
[LICENSES](LICENSES).

## How Tokra is made

Tokra's maintainer describes the three ways code and prose come to exist
like this:

> I use three words for how code and prose comes to exist. Code or prose I wrote, I typed by hand, with nothing generated. Code or prose I wrought, an AI agent generated while I iterated with it, and I reviewed every change before committing it, so I take responsibility for every diff. Code or prose I requested, an agent built with little or no review from me, in the style of a "dark factory."

Tokra's early work was wrought; the rest is requested. AI agents
generated its code, tests, and documentation, this README included,
under the rules in [AGENTS.md](AGENTS.md), and commits name the model
in their footer. For the requested work, independent agent reviews
and the gate that CI runs stand in for the maintainer's review: tests
against real windows on Linux, macOS, and Windows, plus RuboCop, Steep,
RBS, RDoc coverage, Clippy, REUSE, and a check that loads each packaged
gem outside the repository. On
[declare-ai.org](https://declare-ai.org/1.0.0/assess.html)'s scale the
assistance is [creative](https://declare-ai.org/1.0.0/creative.html),
not none, non-creative, or total, because the agents made design and
wording choices under the maintainer's direction.
