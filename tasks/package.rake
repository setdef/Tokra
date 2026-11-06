# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "package_check"

# Smoke-script lines that make a directory, +config_dir+, holding the
# icons/icon.png every app's config needs beside it: a 2x1 RGBA PNG, which
# the extension's png decoder reads as Tauri's codegen does (plan 054,
# phase 3).
SMOKE_CONFIG_DIR = <<~RUBY
  require "tmpdir"
  config_dir = Dir.mktmpdir
  Dir.mkdir(File.join(config_dir, "icons"))
  File.binwrite(File.join(config_dir, "icons", "icon.png"), ["89504e470d0a1a0a0000000d4948445200000002000000010806000000f4227f8a0000000e49444154789c63f8cfc00042ff010ff903fd851199760000000049454e44ae426082"].pack("H*"))
RUBY

# The gems this repository publishes, in dependency order. Each packaged
# list matches its gemspec's; a new top-level path belongs in both.
PACKAGES = [
  PackageCheck::Target.new(
    name: "tokra",
    dir: ".",
    packaged: %w[lib sig ext/tokra Cargo.toml Cargo.lock README.rdoc CHANGELOG.md LICENSE LICENSES],
    generated: ["lib/tokra/js/*"],
    crate: "ext/tokra",
    extension: "lib/tokra/tokra",
    smoke: <<~RUBY),
      require "tokra"
      require "tmpdir"
      # An app built from a config file, as an app is, whose
      # withGlobalTauri adds the API bundle; then every script App#run
      # injects, each from a packaged template (Native.load_js_template).
      #{SMOKE_CONFIG_DIR.chomp}
      config = File.join(config_dir, "tokra.conf.json")
      File.write(config, '{ "identifier": "com.tokra.smoke", "app": { "withGlobalTauri": true } }')
      context = Tokra.generate_context(config)
      abort "the default window icon did not decode" unless context.default_window_icon&.width == 2
      app = Tokra::Builder.default.build(context)
      scripts = app.handle.webview_manager.initialization_scripts("main", "main")
      # The event scripts a listen and an emit render (plan 047).
      Tokra::Event.listen_js_script("o", '{"kind":"Any"}', "tokra://smoke", 0, 1)
      Tokra::Event.emit_js_script("f", Tokra::Event::EmitArgs.new(event: "tokra://smoke", payload: "null"), "[]")
      abort "no home directory from the native extension" unless Tokra::Native.home_dir.is_a?(String)
      abort "Native::EventLoop missing" unless Tokra::Native::EventLoop.method_defined?(:run)
      # ferro-url, from its own installed gem, reads the config's URLs.
      dev_url = Tokra::Utils::Config::BuildConfig.deserialize({ "devUrl" => "HTTP://LocalHost:1420/a/../b" }).dev_url
      abort "ferro-url did not read the config's URL" unless dev_url.as_str == "http://localhost:1420/b"
      puts "tokra \#{Tokra::VERSION} loads; \#{scripts.size} initialization scripts render"
    RUBY
  PackageCheck::Target.new(
    name: "tokra-clipboard",
    dir: "plugins/clipboard",
    packaged: %w[lib sig README.rdoc],
    generated: [],
    crate: nil,
    extension: nil,
    smoke: <<~RUBY),
      require "tokra-clipboard"
      require "tokra/plugins/clipboard/version"
      # ferro-arboard comes from its own installed gem, extension and all:
      # the plugin opens arboard's clipboard through it. Nothing is read or
      # written: this runs in whatever session runs the gate, and its
      # clipboard is the person's, which may hold what no text restores.
      clipboard = Tokra::Plugins::Clipboard::Clipboard.new
      error = clipboard.instance_variable_get(:@error)
      abort "arboard could not open the clipboard: \#{error}" if error
      native = clipboard.instance_variable_get(:@clipboard)
      abort "the plugin did not open ferro-arboard's clipboard" unless native.instance_of?(Ferro::Arboard::Clipboard)
      abort "ferro-arboard lost its native calls" unless Ferro::Arboard::Clipboard.private_method_defined?(:native_set_text)
      puts "tokra-clipboard \#{Tokra::Plugins::Clipboard::VERSION} opens the clipboard through ferro-arboard"
    RUBY
  PackageCheck::Target.new(
    name: "tokra-dialog",
    dir: "plugins/dialog",
    packaged: %w[lib sig README.rdoc],
    generated: [],
    crate: nil,
    extension: nil,
    smoke: <<~RUBY),
      require "tokra-dialog"
      require "tokra/plugins/dialog/version"
      # ferro-rfd comes from its own installed gem, extension and all; the
      # init script is a packaged file the plugin reads at load.
      script = Tokra::Plugins::Dialog::Plugin::INIT_SCRIPT
      abort "the init script lost alert" unless script.include?("plugin:dialog|message")
      #{SMOKE_CONFIG_DIR.chomp}
      config = Tokra::Config.new(identifier: "com.tokra.smoke")
      context = Tokra::Codegen.context_codegen(Tokra::Codegen::ContextData.new(dev: true, config:, config_parent: config_dir))
      handle = Tokra::Builder.default.build(context).handle
      builder = Tokra::Plugins::Dialog::Dialog.new(handle).file.set_title("smoke")
      abort "ferro-rfd lost the title" unless builder.to_async_file_dialog.debug.include?(%(title: Some("smoke")))
      puts "tokra-dialog \#{Tokra::Plugins::Dialog::VERSION} builds an rfd dialog through ferro-rfd"
    RUBY
  PackageCheck::Target.new(
    name: "tokra-notification",
    dir: "plugins/notification",
    packaged: %w[lib sig README.rdoc],
    generated: [],
    crate: nil,
    extension: nil,
    smoke: <<~RUBY),
      require "tokra-notification"
      require "tokra/plugins/notification/version"
      # ferro-notify-rust comes from its own installed gem, extension and
      # all; the init script is a packaged file the plugin reads at load.
      # Nothing is sent: on macOS a send would name the app for good.
      script = Tokra::Plugins::Notification::Plugin::INIT_SCRIPT
      abort "the init script lost notify" unless script.include?("plugin:notification|notify")
      abort "the init script kept its template" if script.include?("__TEMPLATE_windows__")
      #{SMOKE_CONFIG_DIR.chomp}
      config = Tokra::Config.new(identifier: "com.tokra.smoke")
      context = Tokra::Codegen.context_codegen(Tokra::Codegen::ContextData.new(dev: true, config:, config_parent: config_dir))
      handle = Tokra::Builder.default.build(context).handle
      builder = Tokra::Plugins::Notification::Notification.new(handle).builder.title("smoke")
      notification = builder.__send__(:desktop_notification).to_notify_rust
      abort "ferro-notify-rust lost the summary" unless notification.summary == "smoke"
      # ferro-url, likewise, reads an attachment's URL.
      options = { "options" => { "attachments" => [{ "id" => "a", "url" => "HTTP://EXAMPLE.com:80/a/../b" }] } }
      data = Tokra::Plugins::Notification::Commands::Arguments.new(options, "notify").notification_data
      abort "ferro-url did not parse the attachment" unless data.attachments.first.url.as_str == "http://example.com/b"
      # ferro-time reads a scheduled date.
      options = { "options" => { "schedule" => { "at" => { "date" => "2026-10-26T14:00+02:00" } } } }
      date = Tokra::Plugins::Notification::Commands::Arguments.new(options, "notify").notification_data.schedule.date
      abort "ferro-time did not parse the date" unless date.unix_timestamp == 1_793_016_000 && date.offset.whole_hours == 2
      puts "tokra-notification \#{Tokra::Plugins::Notification::VERSION} builds a notification and reads a URL and a date through Ferro"
    RUBY
  PackageCheck::Target.new(
    name: "tokra-global-shortcut",
    dir: "plugins/global-shortcut",
    packaged: %w[lib sig README.rdoc],
    generated: [],
    crate: nil,
    extension: nil,
    smoke: <<~RUBY),
      require "tokra-global-shortcut"
      require "tokra/plugins/global_shortcut/version"
      # ferro-global-hotkey comes from its own installed gem, extension and
      # all. Nothing is registered: a manager would take the keys from the
      # whole desktop.
      plugin = Tokra::Plugins::GlobalShortcut
      builder = plugin::Builder.new.with_shortcut("ctrl+alt+shift+super+F19")
      abort "ferro-global-hotkey lost the shortcut" unless builder.shortcuts.first.into_string == "shift+control+alt+meta+F19"
      abort "the plugin lost its commands" unless plugin::Plugin::COMMANDS.include?("register")
      puts "tokra-global-shortcut \#{plugin::VERSION} parses a shortcut through ferro-global-hotkey"
    RUBY
  PackageCheck::Target.new(
    name: "tokra-log",
    dir: "plugins/log",
    packaged: %w[lib sig README.rdoc],
    generated: [],
    crate: nil,
    extension: nil,
    smoke: <<~RUBY),
      require "tokra-log"
      require "tokra/plugins/log/version"
      builder = Tokra::Plugins::Log::Builder.new.level(:info)
      abort "builder lost its level" unless builder.configured_level == :info
      puts "tokra-log \#{Tokra::Plugins::Log::VERSION} loads"
    RUBY
].freeze

namespace :package do
  # The packaging check resolves each crate with cargo metadata --offline,
  # which needs every platform's dependencies in Cargo's cache; compiling
  # downloads only this machine's.
  desc "Download every platform's locked crates for each Cargo workspace"
  task :fetch do
    CARGO_WORKSPACES.each { |dir| cargo!("fetch", "--locked", chdir: dir) }
  end

  desc "Build each gem and load it from its package, with the compiled extensions (fast)"
  task check: %w[compile package:fetch] do
    PackageCheck.new(root: Dir.pwd, gems: PACKAGES).fast
  rescue PackageCheck::Failure => e
    abort "❌ #{e.message}"
  end

  desc "Install each gem into an empty GEM_HOME, compiling from the packaged sources (slow)"
  task :install do
    PackageCheck.new(root: Dir.pwd, gems: PACKAGES).full
  rescue PackageCheck::Failure => e
    abort "❌ #{e.message}"
  end
end
