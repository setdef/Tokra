# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Fixture for webview_window_builder_test.rb: windows made at run time
# through Tokra::WebviewWindowBuilder (plan 052, phase 2), on the main
# thread from a command and from a Ruby thread. A plugin registered before
# App#run hears every window, "main" included, and "main"'s page listens
# for both created events with @tauri-apps/api's listen.
#
# It prints, each from the hook that hears it:
#
#   PLUGIN <hook> <label>             the created plugin's window_created, webview_created
#   SETUP main=<bool>                 whether the setup hook finds "main"
#   REQUEST <label> <path>            the path of each page a webview asks for
#   BUILT cmd <title>                 the title "cmd" answers as its build returns
#   TITLE thread <title>              "thread"'s title, asked from the thread that built it
#   HEARD <label> <event> <event>     the order "main"'s page heard both events for <label>
#   PAGE <label> finished             a page load, from Builder#on_page_load
#   SIZE cmd <width>x<height>         "cmd"'s logical inner size once its page loaded
#   INNER <label> <height>            on macOS, the page's innerHeight in "bar-visible",
#                                     the default Visible title bar, and "bar-transparent"
#   EVENT exit-requested <code> | EVENT exit
#
# "main"'s page invokes make once both listeners are in. make builds "cmd"
# at once, on the main thread, and starts a Ruby thread that builds
# "thread" and at once asks its title, which waits behind the creation.
# When every line above has come, the app exits.
#
#   bundle exec ruby test/integration/fixtures/webview_window_builder/app.rb

require_relative "../../support/fixture_app"

$stdout.sync = true

module WebviewWindowBuilderFixture
  # "main"'s page: both listeners, then make. Each label's two events are
  # reported in one invoke, in the order the page heard them.
  MAIN_PAGE = <<~HTML
    <!doctype html><meta charset=utf-8><title>builder</title><p>main</p>
    <script>
      const { listen } = window.__TAURI__.event
      const { invoke } = window.__TAURI__.core
      const heard = {}
      const hear = (event) => {
        const label = event.payload.label
        const order = (heard[label] ||= [])
        order.push(event.event)
        if (order.length === 2) invoke('heard', { label, order })
      }
      ;(async () => {
        await listen('tauri://webview-created', hear)
        await listen('tauri://window-created', hear)
        await invoke('make')
      })()
    </script>
  HTML

  # The page each built window opens.
  PAGE = "<!doctype html><meta charset=utf-8><title>built</title><p>built</p>"

  # The page of each title-bar window, which reports its innerHeight.
  BAR_PAGE = <<~HTML
    <!doctype html><meta charset=utf-8><title>bar</title><p>bar</p>
    <script>
      addEventListener('load', () => {
        window.__TAURI__.core.invoke('inner', { height: window.innerHeight })
      })
    </script>
  HTML

  # On macOS, the two title-bar windows, each 240 by 180: Visible, the
  # default, lays the page under its title bar (a full-size content view),
  # and Transparent below it (tauri-runtime-wry lib.rs:1151-1176).
  MACOS = RUBY_PLATFORM.include?("darwin")

  # What must happen before the app exits.
  STEPS = (%w[page:cmd page:thread heard:cmd heard:thread title:thread] +
    (MACOS ? %w[inner:bar-visible inner:bar-transparent] : [])).freeze

  # Records +step+ on the main thread and exits once every one of STEPS
  # has happened.
  def self.step(handle, step)
    done = (Thread.current[:webview_window_builder_done] ||= [])
    done << step
    handle.exit(0) if (STEPS - done).empty?
  end

  # Prints each created hook.
  class CreatedPlugin < Tokra::Plugin
    def name = "created"
    def window_created(window) = puts("PLUGIN window_created #{window.label}")
    def webview_created(webview) = puts("PLUGIN webview_created #{webview.label}")
  end

  SETUP = Ractor.shareable_proc do |app|
    FixtureApp.background(app)
    main = app.get_webview_window("main")
    puts "SETUP main=#{!main.nil?}"
    FixtureApp.keep_in_sight(main.window) if main
  end

  # Serves "main"'s page at / and the built windows' pages elsewhere.
  # Prints the path each webview asked for, which its WebviewUrl named.
  PROTOCOL = Ractor.shareable_proc do |context, request|
    puts "REQUEST #{context.webview_label} #{Ferro::Url::Url.parse(request.uri).path}"
    label = context.webview_label
    page = if label == "main" then MAIN_PAGE
    elsif label.start_with?("bar-") then BAR_PAGE
    else PAGE
    end
    Tokra::Response.ok(page)
  end

  PAGE_LOAD = Ractor.shareable_proc do |webview, payload|
    next unless payload.finished? && webview.label != "main"

    puts "PAGE #{webview.label} finished"
    if webview.label == "cmd"
      window = webview.window
      size = window.inner_size
      scale = window.scale_factor
      puts "SIZE cmd #{(size.width / scale).round}x#{(size.height / scale).round}"
    end
    WebviewWindowBuilderFixture.step(webview.app_handle, "page:#{webview.label}")
  end

  COMMANDS = Ractor.shareable_proc do |invoke|
    handle = invoke.webview.app_handle
    case invoke.command
    when "make"
      url = Tokra::WebviewUrl::App.new("cmd.html")
      cmd = Tokra::WebviewWindowBuilder.new(invoke.webview, "cmd", url).title("built (cmd)").inner_size(240, 180)
        .build
      FixtureApp.keep_in_sight(cmd.window)
      puts "BUILT cmd #{cmd.title}"
      Thread.new do
        url = Tokra::WebviewUrl::App.new("thread.html")
        thread = Tokra::WebviewWindowBuilder.new(handle, "thread", url).title("built (thread)").inner_size(240, 180)
          .build
        # A query waits for the main thread, behind the creation, so it
        # finds the window built; ahead of it, it would find none and raise.
        puts "TITLE thread #{thread.title}"
        FixtureApp.keep_in_sight(thread.window)
        handle.run_on_main_thread { WebviewWindowBuilderFixture.step(handle, "title:thread") }
      end
      if WebviewWindowBuilderFixture::MACOS
        bars = [["bar-visible", nil], ["bar-transparent", Tokra::TitleBarStyle::Transparent]]
        bars.each do |label, style|
          builder = Tokra::WebviewWindowBuilder.new(invoke.webview, label, Tokra::WebviewUrl::App.new("bar.html"))
            .inner_size(240, 180)
          builder.title_bar_style(style) if style
          FixtureApp.keep_in_sight(builder.build.window)
        end
      end
      invoke.resolve(nil)
    when "inner"
      label = invoke.webview.label
      puts "INNER #{label} #{invoke.payload['height']}"
      invoke.resolve(nil)
      WebviewWindowBuilderFixture.step(handle, "inner:#{label}")
    when "heard"
      label = invoke.payload["label"]
      puts "HEARD #{label} #{invoke.payload['order'].join(' ')}"
      invoke.resolve(nil)
      WebviewWindowBuilderFixture.step(handle, "heard:#{label}")
    else next false
    end
    true
  end
end

app = Tokra::Builder.default
  .title("Tokra integration: webview window builder")
  .size(320, 240)
  .with_global_tauri
  .register_uri_scheme_protocol("tokra", &WebviewWindowBuilderFixture::PROTOCOL)
  .on_page_load(&WebviewWindowBuilderFixture::PAGE_LOAD)
  .invoke_handler(&WebviewWindowBuilderFixture::COMMANDS)
  .setup(&WebviewWindowBuilderFixture::SETUP)
  .build
# Before App#run, so the plugin hears "main" too.
app.handle.plugin(WebviewWindowBuilderFixture::CreatedPlugin.new(app.handle))
app.run do |_handle, event|
  case event
  when Tokra::RunEvent::ExitRequested then puts "EVENT exit-requested #{event.code.inspect}"
  when Tokra::RunEvent::Exit then puts "EVENT exit"
  end
end
