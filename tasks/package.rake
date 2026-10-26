# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "package_check"

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
      # Assemble every script App#run injects; each comes from a packaged
      # template (Native.load_js_template).
      app = Tokra::Builder.default.with_global_tauri.build
      scripts = app.__send__(:initialization_scripts)
      Tokra::Native.emit_js_script("tokra://smoke", "null")
      abort "no home directory from the native extension" unless Tokra::Native.home_dir.is_a?(String)
      abort "Native::EventLoop missing" unless Tokra::Native::EventLoop.method_defined?(:run)
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
      # ferro-arboard comes from its own installed gem, extension and all.
      clipboard = Tokra::Plugins::Clipboard::Clipboard.new
      clipboard.write_text("tokra-clipboard smoke")
      abort "the clipboard lost its text" unless clipboard.read_text == "tokra-clipboard smoke"
      puts "tokra-clipboard \#{Tokra::Plugins::Clipboard::VERSION} round-trips text through ferro-arboard"
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
      handle = Tokra::Builder.default.build.handle
      builder = Tokra::Plugins::Dialog::Dialog.new(handle).file.set_title("smoke")
      abort "ferro-rfd lost the title" unless builder.to_async_file_dialog.inspect.include?(%(title: Some("smoke")))
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
      handle = Tokra::Builder.default.build.handle
      builder = Tokra::Plugins::Notification::Notification.new(handle).builder.title("smoke")
      notification = builder.__send__(:desktop_notification).to_notify_rust
      abort "ferro-notify-rust lost the summary" unless notification.summary == "smoke"
      puts "tokra-notification \#{Tokra::Plugins::Notification::VERSION} builds a notification through ferro-notify-rust"
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
