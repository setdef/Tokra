# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# The app half of the real-window integration tests. Each fixture app under
# test/integration/fixtures/ requires this file, builds on FixtureApp.builder,
# and runs. RealApp (real_app.rb) launches it in a child process.
#
# The contract between the two halves is a few stdout lines:
#
#   EVENT ready | EVENT window <class> | EVENT exit   run events a plugin heard
#   REPORT <json>                                     the page's check results
#
# The page reports over a Rack POST, not IPC, so a broken IPC layer still
# produces a report. Then, unless --wait was given, it asks Ruby to exit
# through plugin:fixture|exit with --exit-code (default 0) when every check
# passed, and 1 when one failed.

require_relative "../../../lib/tokra"
require "json"
require "optparse"

module FixtureApp
  HARNESS = File.expand_path("../fixtures/harness.js", __dir__)

  # Options every fixture accepts, plus +flags+ the fixture names.
  def self.options(argv, *flags)
    values = { exit_code: 0, wait: false }
    OptionParser.new do |parser|
      parser.on("--exit-code=CODE", Integer) { |code| values[:exit_code] = code }
      parser.on("--wait") { values[:wait] = true }
      flags.each { |flag| parser.on("--#{flag.to_s.tr('_', '-')}") { values[flag] = true } }
    end.parse!(argv)
    values
  end

  # The Rack app a fixture serves over tokra://: its index.html, the shared
  # harness, its options, the report endpoint, and any +routes+ it adds as
  # <tt>{ "/path" => ->(env) { [status, headers, body] } }</tt>.
  class Site
    def initialize(dir, options, routes = {})
      @dir = dir
      @options = options
      @routes = routes
    end

    def call(env)
      path = env["PATH_INFO"]
      return @routes.fetch(path).call(env) if @routes.key?(path)

      case [env["REQUEST_METHOD"], path]
      in ["GET", "/"] then file(File.join(@dir, "index.html"), "text/html; charset=utf-8")
      in ["GET", "/harness.js"] then file(HARNESS, "text/javascript")
      in ["GET", "/options.json"] then json(exitCode: @options[:exit_code], wait: @options[:wait])
      in ["POST", "/report"] then report(env["rack.input"].read)
      else [404, { "content-type" => "text/plain" }, ["not found"]]
      end
    end

    private def file(path, type)
      [200, { "content-type" => type }, [File.binread(path)]]
    end

    private def json(value)
      [200, { "content-type" => "application/json" }, [JSON.generate(value)]]
    end

    private def report(body)
      puts "REPORT #{JSON.generate(JSON.parse(body))}"
      # The test may act on the report (send Ctrl-C) before the app exits.
      $stdout.flush
      [204, {}, []]
    end
  end

  # Prints the run events it hears, and serves plugin:fixture|exit so the
  # page can end the app through AppHandle#exit.
  class Plugin < Tokra::Plugin
    def name
      "fixture"
    end

    def on_event(_app, event)
      case event
      when Tokra::RunEvent::Ready then puts "EVENT ready"
      when Tokra::RunEvent::WindowEvent then puts "EVENT window #{event.event.class.name}"
      when Tokra::RunEvent::Exit then puts "EVENT exit"
      end
    end

    def extend_api(invoke)
      return false unless invoke.command == "exit"

      app.exit(Integer(invoke.payload.fetch("code")))
    end
  end

  # A Builder serving +site+ with the fixture plugin registered, and one
  # instance of each class in +plugins+ beside it.
  def self.builder(site, title, plugins: [])
    classes = Ractor.make_shareable([FixtureApp::Plugin, *plugins])
    Tokra::Builder.default
      .title("Tokra integration: #{title}")
      .size(480, 360)
      .app(site)
      .setup(&Ractor.shareable_proc { |app| classes.each { |plugin| app.handle.plugin(plugin.new(app.handle)) } })
  end
end
