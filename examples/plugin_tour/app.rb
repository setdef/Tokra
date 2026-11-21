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
require "ferro/time"

# The tour's constants, kept in one namespace.
module PluginTour
  # The files the page loads, by request path: only the page. Each
  # plugin's global API script (+api-iife.js+) comes from its gem, which
  # Tokra injects for an app that sets +withGlobalTauri+, as Tauri does.
  FILES = {
    "/" => ["index.html", "text/html; charset=utf-8"],
  }.freeze

  # The date and time at the start of each log line, in the layout of
  # Tauri's log plugin (<tt>[2026-11-13][09:41:00]</tt>), read by the time
  # crate through ferro-time, as Tauri's are.
  LOG_TIME = Ractor.make_shareable(
    Ferro::Time::FormatDescription.parse_borrowed(1, "[[[year]-[month]-[day]][[[hour]:[minute]:[second]]")
  )

  # Formats a terminal log line as Tauri's log plugin does by default, in
  # UTC: the date and time, the level, and the message.
  LOG_FORMAT = Ractor.shareable_proc do |severity, _time, _progname, message|
    "#{Ferro::Time::OffsetDateTime.now_utc.format(LOG_TIME)}[#{severity}] #{message}\n"
  end
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

# The tour's own commands. +log_message+ writes the page's line through
# the log plugin; +page_url+ answers the page's address as Tokra reads it.
commands = Ractor.shareable_proc do |invoke|
  case invoke.command
  when "log_message"
    invoke.webview.state(Tokra::Plugins::Log::Plugin).info(invoke.payload["message"].to_s)
    invoke.resolve(nil)
  when "page_url"
    url = invoke.webview.url
    invoke.resolve({ href: url.as_str, scheme: url.scheme, host: url.host_str, path: url.path })
  else
    next false
  end
  true
end

app = Tokra::Builder.default
  .app(site)
  .invoke_handler(&commands)
  .plugin(Tokra::Plugins::Clipboard.init)
  .plugin(Tokra::Plugins::Dialog.init)
  .plugin(Tokra::Plugins::GlobalShortcut::Builder.new.build)
  .plugin(Tokra::Plugins::Notification.init)
  .build(Tokra.generate_context)
handle = app.handle

# The log plugin writes to the terminal and to the page, which hears each
# line as a <tt>log://log</tt> event. The commands above reach it through
# managed state.
log = Tokra::Plugins::Log::Builder.new
  .app_handle(handle)
  .level(:info)
  .targets([
    Tokra::Plugins::Log::Target.new($stdout).format(PluginTour::LOG_FORMAT),
    Tokra::Plugins::Log::Target.new(Tokra::Plugins::Log::TargetKind::Webview.new),
  ])
  .build
handle.plugin(log)
handle.manage(log)

app.run
