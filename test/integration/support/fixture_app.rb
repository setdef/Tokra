# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# The app half of the real-window integration tests. Each fixture app under
# test/integration/fixtures/ requires this file, builds on FixtureApp.builder,
# and runs with the context its tokra.conf.json describes, as an app does.
# RealApp (real_app.rb) launches it in a child process.
#
# The contract between the two halves is a few stdout lines:
#
#   EVENT ready | EVENT window <class>                run events a plugin heard
#                                                     (a window's close and destruction)
#   EVENT exit-requested <code> | EVENT exit
#   REPORT <json>                                     the page's check results
#   PROGRESS <stage> <seconds>                        how far a fixture got
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

  # When this file loaded, on the monotonic clock.
  STARTED = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  # Prints that the fixture reached +stage+, with the seconds since it
  # loaded, and flushes, so the harness's message for a hung fixture shows
  # the last stage it reached (plan 051).
  def self.progress(stage)
    seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - STARTED
    $stdout.write("PROGRESS #{stage} #{format('%.3f', seconds)}\n")
    $stdout.flush
  end

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

    def on_event(app, event)
      case event
      when Tokra::RunEvent::Ready
        FixtureApp.keep_in_sight(app.get_window("main"))
        puts "EVENT ready"
      # The close and its end only: when the platform reports a resize, a
      # move, or a focus change depends on its window manager.
      when Tokra::RunEvent::WindowEvent
        case event.event
        when Tokra::WindowEvent::CloseRequested, Tokra::WindowEvent::Destroyed
          puts "EVENT window #{event.event.class.name}"
        end
      when Tokra::RunEvent::ExitRequested then puts "EVENT exit-requested #{event.code.inspect}"
      when Tokra::RunEvent::Exit then puts "EVENT exit"
      end
    end

    def extend_api(invoke)
      return false unless invoke.command == "exit"

      app.exit(Integer(invoke.payload.fetch("code")))
      invoke.resolve(nil)
      true
    end
  end

  # A Builder that registers one instance of each of its plugin classes on
  # the app it builds, before App#run, so each plugin's initialization
  # script reaches the config's windows, which the app makes before its
  # setup hook (plan 052, decision b1).
  class Builder < Tokra::Builder
    def initialize(plugin_classes)
      super()
      @plugin_classes = plugin_classes
    end

    def build(context, native: Tokra::Native)
      app = super
      @plugin_classes.each { |plugin| app.handle.plugin(plugin.new(app.handle)) }
      app
    end
  end

  # The fixture's context: the tokra.conf.json beside the fixture, read as
  # an app's is (Tokra.generate_context). +title+, when given, replaces the
  # first window's, for a fixture whose title has to be one no other
  # window on the display has.
  def self.context(title: nil)
    context = Tokra.generate_context
    return context unless title

    app = context.config.app
    first, *rest = app.windows
    context.config = context.config.with(app: app.with(windows: [first.with(title:), *rest]))
    context
  end

  # Makes every window a fixture builds, "main" included, keep its page
  # running when the window is unseen. When the test process's login
  # session is off the console (fast user switching, a hidden test
  # account), macOS WebKit counts every window as unseen, sends the page
  # PrepareToSuspend once it loads, and stops its JavaScript a few seconds
  # later, so a fixture whose page drives the test hangs. Disabled
  # BackgroundThrottlingPolicy prevents the suspension.
  #
  # The config's windows are built inside App#run with no hook for webview
  # rows, and the product default must stay Tauri's, so the fixtures
  # prepend this to WebviewWindowBuilder#build instead. A fixture that chose its own policy
  # keeps it. A Tauri fixture would set backgroundThrottling on its config
  # window instead (tauri-utils config.rs:1925); once plan 054a-4 builds
  # config windows, the fixtures should set it in tokra.conf.json and this
  # stand-in should go.
  module Unthrottled
    def build
      webview_row do |rows|
        rows.background_throttling(Tokra::BackgroundThrottlingPolicy::Disabled) if rows.native_attributes[:background_throttling].nil?
      end
      super
    end
  end
  Tokra::WebviewWindowBuilder.prepend(Unthrottled)

  # Each line of the contract is read whole, but a fixture prints from
  # its event loop, its page's hooks, and its own server threads at once.
  # Where Ruby has no writev, as on Windows, or $stdout is neither synced
  # nor a terminal, IO#puts writes a line and its newline as two pieces,
  # with a thread switch between them (io.c, io_writev and io_binwrite),
  # so another thread's line can land in the gap, as "REQUEST
  # /favicon.ico cookie=pageEVENT exit" once did. Extending the fixture's
  # $stdout with this makes each puts a single write, which Ruby keeps
  # whole across threads. It matches IO#puts for what fixtures print:
  # strings, nil, and flat or nested arrays of them.
  module WholeLines
    def puts(*objects)
      lines = objects.empty? ? [""] : objects.flatten
      write(lines.map { |object| (line = object.to_s).end_with?("\n") ? line : "#{line}\n" }.join)
      nil
    end
  end
  $stdout.extend(WholeLines)

  # A Builder serving +site+ with the fixture plugin registered, and one
  # instance of each class in +plugins+ beside it. Its window's title and
  # size are the fixture's tokra.conf.json's. On macOS the app runs in the
  # background, so it never takes the keyboard from the person at the
  # machine (FixtureApp.background).
  def self.builder(site, plugins: [])
    Builder.new([FixtureApp::Plugin, *plugins])
      .app(site)
      .setup(&Ractor.shareable_proc { |app| FixtureApp.background(app) })
  end

  # Keeps +app+ from ever becoming the active app on macOS. tao activates
  # an app as it finishes launching (tao 0.34.5
  # platform_impl/macos/app_state.rs:285-295), which brings its window to
  # the front and takes keyboard focus. With the Prohibited policy AppKit
  # refuses the activation, and the window still opens, draws, and runs
  # its page. Elsewhere it does nothing: Tauri defines activation policies
  # only on macOS.
  def self.background(app)
    return unless app.respond_to?(:set_activation_policy)

    app.set_activation_policy(Tokra::ActivationPolicy::Prohibited)
  end

  # Keeps a background app's +window+ in sight on macOS, without letting
  # it catch a click. A window that never comes to the front opens behind
  # whatever window is there. WebKit treats a page whose window is covered
  # as a background page and lowers its processes to background priority,
  # and on a busy machine such a page stalls mid-check. Kept above other
  # windows it stays visible and runs, the app still never takes the
  # keyboard, and clicks meant for the app beneath pass through it.
  # Elsewhere the window came to the front on its own, so this does
  # nothing.
  def self.keep_in_sight(window)
    return unless Tokra.const_defined?(:ActivationPolicy)

    window.set_always_on_top(true)
    window.set_ignore_cursor_events(true)
  end
end
