<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: MIT-0
-->

# The plugin tour

One window that puts five of Tokra's first-party plugins to work, and
the [Ferro](https://github.com/setdef/Ferro) gem under each. The page
calls Tauri's own JavaScript API, so it reads as a Tauri page would.
tokra-process is left out: its two commands end the app or start it
again, which would end the tour.

| Control | The page calls | Plugin | Ferro gem |
|---|---|---|---|
| Copy, Paste | `clipboardManager.writeText`, `readText` | tokra-clipboard | ferro-arboard |
| Open a file, Save as | `dialog.open`, `dialog.save` | tokra-dialog | ferro-rfd |
| Notify me | `notification.sendNotification` | tokra-notification | ferro-notify-rust |
| Register | `globalShortcut.register` | tokra-global-shortcut | ferro-global-hotkey |
| Write a log line | `core.invoke('log_message')`, `event.listen('log://log')` | tokra-log | ferro-time, in `app.rb` |
| Read this page's URL | `core.invoke('page_url')` | Tokra itself | ferro-url |

## What each control shows

**Clipboard.** Copy puts the text field's text on the system clipboard;
paste it into another app to see it there. Paste shows the clipboard's
text, or arboard's error when it holds no text. On Linux the copied text
lasts only while the app runs.

**Dialogs.** Open a file and Save as show the system's dialogs and print
the path you chose, or "Cancelled". The tour never opens or writes the
file. On macOS each dialog is a sheet on the window, and on Windows the
window waits until it closes. On Linux they come from the XDG desktop
portal, or from `zenity` where there is no portal; under Wayland they
have no parent window.

**Notification.** Notify me sends a notification with a title and the
time. On macOS it comes from Terminal, because an app run from source
has no bundle with its identifier. On Windows it comes from PowerShell.
On Linux it goes over D-Bus to the desktop's notification server.
Tauri's notification plugin has no action buttons on desktop systems,
only on iOS and Android, so neither has tokra-notification:
`registerActionTypes` and `onAction` answer `Command NAME not found`.

**Global shortcut.** Register claims ⌘⌥K on macOS, or Ctrl+Alt+K
elsewhere, for the whole desktop. Switch to another app and press it:
the count on the page goes up. Unregister lets it go. On Linux the
shortcut is an X11 key grab, so it works under X11 and XWayland. If
another app already holds the combination, the presses go to that app
and the count stays still.

**Log.** Write a log line sends a line to Ruby, which logs it through
tokra-log to two targets: the terminal, where each line starts with the
date and time in UTC, read through ferro-time in the layout of Tauri's
log plugin; and the page, which hears it as the `log://log` event and
lists it. The page's lines have no time, because tokra-log's page target
ignores the formatter.

**URL.** Read this page's URL asks Ruby for the webview's address, which
Tokra reads with ferro-url, and shows it with its scheme, host, and
path: `tokra://localhost/` on macOS and Linux, `http://tokra.localhost/`
on Windows.

## How it is put together

`app.rb` serves `index.html` through a Rack lambda, registers the five
plugins, and answers the page's two commands. Each plugin's
`api-iife.js`, unchanged from Tauri, puts its API on `window.__TAURI__`.
Each plugin gem ships its script, and because the config sets
`withGlobalTauri`, Tokra injects them into the page. With a bundler, import
`@tauri-apps/plugin-clipboard-manager` and the others instead.

tokra-log has no command the page can call yet, so the page sends its
line through the tour's own `log_message` command, and `app.rb` keeps
the log plugin in managed state to reach it.

## Running it from this checkout

Set up the checkout first, as the root README's Installation section
says (`bundle install` and `bundle exec rake compile` at the root). Then:

```sh
cd examples/plugin_tour
bundle install
bundle exec ruby app.rb
```

The `Gemfile` takes Tokra and the plugins from this checkout, and the
Ferro gems from their release tags.

## Running it from built gems

This runs the tour the way a user who ran `gem install` gets it: every
gem built into a `.gem` file and installed into an empty `GEM_HOME`, with
no Bundler, no checkout, and no git sources. It is what
`bundle exec rake package:install` does to check the gems. Installing
compiles each Rust extension, which takes several minutes.

From the root of a set-up checkout, in a macOS or Linux shell:

```sh
out="$HOME/plugin-tour-gems"
mkdir -p "$out/pkg"

# The Ferro gems, from the checkouts Bundler made of their release tags.
for name in ferro-url ferro-time ferro-arboard ferro-rfd ferro-notify-rust ferro-global-hotkey; do
  (cd "$(bundle info --path "$name")" && gem build "$name.gemspec" --output "$out/pkg/$name.gem")
done

# Tokra and its plugins.
gem build tokra.gemspec --output "$out/pkg/tokra.gem"
for name in clipboard dialog global-shortcut log notification; do
  (cd "plugins/$name" && gem build "tokra-$name.gemspec" --output "$out/pkg/tokra-$name.gem")
done

# Install them, dependencies first, into an empty GEM_HOME.
export GEM_HOME="$out/home"
export GEM_PATH="$GEM_HOME:$(ruby -e 'print Gem.default_dir')"
for name in ferro-url ferro-time ferro-arboard ferro-rfd ferro-notify-rust ferro-global-hotkey \
  tokra tokra-log tokra-clipboard tokra-dialog tokra-notification tokra-global-shortcut; do
  gem install --local --no-document "$out/pkg/$name.gem"
done

# Run a copy of the tour, outside the checkout.
cp -R examples/plugin_tour "$out/plugin_tour"
cd "$out/plugin_tour"
env -u BUNDLE_GEMFILE -u RUBYOPT -u RUBYLIB ruby app.rb
```

`GEM_PATH` keeps Ruby's own gem directory for `rb_sys` and `logger`,
which the gems need and the checkout's `bundle install` put there.
`--local` has each install take only the files you built and the gems
already installed, never RubyGems.org, which has only a `tokra` from
January 2026 and none of the others yet.
