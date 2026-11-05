# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Fixture for web_context_test.rb: webviews built with
# WebviewWindowBuilder#data_directory (plan 052, 052e-3), which share
# their local storage when they name one directory, and only then.
#
# "writer" names the directory SAME and stores a value under a key no
# earlier run used. Once it has, "same" names SAME too and "other" names
# OTHER, and each reads the key back. Then "writer" removes the key, and
# the app exits.
#
# It prints, each from the command that hears it:
#
#   WROTE writer                   "writer" stored the value
#   READ <label> <found>           what "same" or "other" read: shared
#                                  (the writer's value), empty (none),
#                                  or another value
#   CLEARED writer                 "writer" removed the key
#   EVENT exit-requested <code> | EVENT exit
#
#   bundle exec ruby test/integration/fixtures/web_context/app.rb

require_relative "../../support/fixture_app"
require "fileutils"
require "securerandom"
require "tmpdir"

module WebContextFixture
  # The directories, made fresh for this run and removed after it.
  ROOT = Dir.mktmpdir("tokra-web-context").freeze
  SAME = File.join(ROOT, "same").freeze
  OTHER = File.join(ROOT, "other").freeze

  # The value "writer" stores, under a key of its own, so nothing an
  # earlier run left behind can answer for it.
  VALUE = SecureRandom.hex(8).freeze
  KEY = "tokra-web-context-#{VALUE}".freeze

  # "main"'s page, which does nothing.
  MAIN_PAGE = "<!doctype html><meta charset=utf-8><title>web context</title><p>main</p>"

  # "writer"'s page: stores VALUE under KEY.
  WRITER_PAGE = <<~HTML
    <!doctype html><meta charset=utf-8><title>writer</title><p>writer</p>
    <script>
      localStorage.setItem(#{JSON.generate(KEY)}, #{JSON.generate(VALUE)})
      window.__TAURI__.core.invoke('wrote')
    </script>
  HTML
  WRITER_PAGE.freeze

  # The page "same" and "other" load: what KEY holds.
  READER_PAGE = <<~HTML
    <!doctype html><meta charset=utf-8><title>reader</title><p>reader</p>
    <script>
      window.__TAURI__.core.invoke('read', { value: localStorage.getItem(#{JSON.generate(KEY)}) })
    </script>
  HTML
  READER_PAGE.freeze

  # What "writer" runs once both have read: removes KEY, then says so.
  CLEAR = "localStorage.removeItem(#{JSON.generate(KEY)}); window.__TAURI__.core.invoke('cleared')".freeze

  # A webview window of +label+ opening +path+ with its data in
  # +directory+, 240 by 180, kept in sight on macOS.
  def self.build(manager, label, path, directory)
    builder = FixtureApp.webview_window(manager, label, Tokra::WebviewUrl::App.new(path))
      .inner_size(240, 180).data_directory(directory)
    FixtureApp.keep_in_sight(builder.build.window)
  end

  # What a reader found: the writer's value, none, or another.
  def self.found(value)
    case value
    when VALUE then "shared"
    when nil then "empty"
    else "other:#{value}"
    end
  end

  # Records that +label+ has read, on the main thread, and has "writer"
  # clear the key once both have.
  def self.read(handle, label)
    read = (Thread.current[:web_context_read] ||= [])
    read << label
    handle.get_webview_window("writer").eval(CLEAR) if (%w[same other] - read).empty?
  end

  SETUP = Ractor.shareable_proc do |app|
    FixtureApp.background(app)
    FixtureApp.keep_in_sight(app.get_window("main"))
    WebContextFixture.build(app, "writer", "writer.html", WebContextFixture::SAME)
  end

  PROTOCOL = Ractor.shareable_proc do |_context, request|
    case Ferro::Url::Url.parse(request.uri).path
    when "/writer.html" then Tokra::Response.ok(WebContextFixture::WRITER_PAGE)
    when "/reader.html" then Tokra::Response.ok(WebContextFixture::READER_PAGE)
    else Tokra::Response.ok(WebContextFixture::MAIN_PAGE)
    end
  end

  COMMANDS = Ractor.shareable_proc do |invoke|
    handle = invoke.webview.app_handle
    label = invoke.webview.label
    case invoke.command
    when "wrote"
      puts "WROTE #{label}"
      invoke.resolve(nil)
      handle.run_on_main_thread do
        WebContextFixture.build(handle, "same", "reader.html", WebContextFixture::SAME)
        WebContextFixture.build(handle, "other", "reader.html", WebContextFixture::OTHER)
      end
    when "read"
      puts "READ #{label} #{WebContextFixture.found(invoke.payload['value'])}"
      invoke.resolve(nil)
      WebContextFixture.read(handle, label)
    when "cleared"
      puts "CLEARED #{label}"
      invoke.resolve(nil)
      handle.exit(0)
    else next false
    end
    true
  end
end

at_exit { FileUtils.rm_rf(WebContextFixture::ROOT) }

app = Tokra::Builder.default
  .register_uri_scheme_protocol("tokra", &WebContextFixture::PROTOCOL)
  .invoke_handler(&WebContextFixture::COMMANDS)
  .setup(&WebContextFixture::SETUP)
  .build(Tokra.generate_context)
app.run do |_handle, event|
  case event
  when Tokra::RunEvent::ExitRequested then puts "EVENT exit-requested #{event.code.inspect}"
  when Tokra::RunEvent::Exit then puts "EVENT exit"
  end
end
