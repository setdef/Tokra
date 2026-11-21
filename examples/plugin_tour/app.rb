# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

# The plugin tour: one window that puts five first-party plugins to work,
# from a page that calls Tauri's own JavaScript API. README.md beside this
# file says what each control shows and how to run it.

require "tokra"
require "tokra-clipboard"
require "tokra-dialog"
require "tokra-global-shortcut"
require "tokra-log"
require "tokra-notification"

# The tour's constants, kept in one namespace.
module PluginTour
  # The files the page loads, by request path: only the page. Each
  # plugin's global API script (+api-iife.js+) comes from its gem, which
  # Tokra injects for an app that sets +withGlobalTauri+, as Tauri does.
  FILES = {
    "/" => ["index.html", "text/html; charset=utf-8"],
  }.freeze
end

# Serves the page from this folder.
site = lambda do |env|
  file, type = PluginTour::FILES[env["PATH_INFO"]]
  if file
    [200, { "content-type" => type }, [File.read(File.join(__dir__, file))]]
  else
    [404, { "content-type" => "text/plain" }, ["Not found"]]
  end
end

# The tour's own command: +page_url+ answers the page's address as Tokra
# reads it.
commands = Ractor.shareable_proc do |invoke|
  next false unless invoke.command == "page_url"

  url = invoke.webview.url
  invoke.resolve({ href: url.as_str, scheme: url.scheme, host: url.host_str, path: url.path })
  true
end

# The log plugin writes each line, the page's included, to the terminal
# and to the page, which hears it as a <tt>log://log</tt> event.
log = Tokra::Plugins::Log::Builder.new
  .level(:info)
  .targets([
    Tokra::Plugins::Log::Target.new(Tokra::Plugins::Log::TargetKind::Stdout.new),
    Tokra::Plugins::Log::Target.new(Tokra::Plugins::Log::TargetKind::Webview.new),
  ])
  .build

Tokra::Builder.default
  .app(site)
  .invoke_handler(&commands)
  .plugin(Tokra::Plugins::Clipboard.init)
  .plugin(Tokra::Plugins::Dialog.init)
  .plugin(Tokra::Plugins::GlobalShortcut::Builder.new.build)
  .plugin(log)
  .plugin(Tokra::Plugins::Notification.init)
  .run(Tokra.generate_context)
