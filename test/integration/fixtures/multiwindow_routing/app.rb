# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Fixture for multiwindow_routing_test.rb: two real windows, each event
# routed by its label (plan 052, phase 1). The setup hook builds a second
# window "second" holding a webview "side" through Tokra::Native and
# registers both by hand, as phase 2's WebviewWindowBuilder will. Each
# webview loads a page over tokra://.
#
# It prints, each from the hook that hears it:
#
#   PROTOCOL <webview label>         a tokra:// request, from its context
#   PAGE <webview label> <event>     a page load, from Builder#on_page_load
#   INVOKE <webview label> <via>     an invoke of whoami, from the command
#   EVENT <window label> <class>     a window's CloseRequested and Destroyed
#   EVENT exit-requested <code> | EVENT exit
#
# "side"'s page invokes whoami twice: through the injected
# __TAURI_INTERNALS__.invoke, which posts to ipc:// (ipc-protocol.js), and
# through wry's window.ipc.postMessage with the message Tauri's client
# would send there, its invoke key included, as the client falls back to
# when ipc:// fails. When both webviews have loaded and both invokes have
# arrived it closes "second"; when "second" is destroyed it closes "main",
# and the app exits as its last window goes.
#
#   bundle exec ruby test/integration/fixtures/multiwindow_routing/app.rb

require_relative "../../support/fixture_app"

$stdout.sync = true

module MultiwindowRoutingFixture
  # "main"'s page; it loads nothing else.
  PAGE = "<!doctype html><meta charset=utf-8><title>routing</title><p>routing</p>"

  # "side"'s page, which invokes whoami once over each transport.
  # INVOKE_KEY_LITERAL becomes the app's invoke key, which postMessage
  # carries in the message.
  SIDE_PAGE = <<~HTML
    <!doctype html><meta charset=utf-8><title>routing</title><p>side</p>
    <script>
      const internals = window.__TAURI_INTERNALS__
      internals.invoke('whoami', { via: 'ipc-protocol' })
      const callback = internals.transformCallback(() => {}, true)
      const error = internals.transformCallback(() => {}, true)
      window.ipc.postMessage(JSON.stringify({
        cmd: 'whoami', callback, error, payload: { via: 'post-message' },
        __TAURI_INVOKE_KEY__: INVOKE_KEY_LITERAL
      }))
    </script>
  HTML

  # What must happen before "second" closes.
  STEPS = %w[page:main page:side invoke:ipc-protocol invoke:post-message].freeze

  # Records +step+ on the main thread, where page loads and invokes
  # arrive, and closes "second" once every one of STEPS has happened.
  def self.step(handle, step)
    done = (Thread.current[:multiwindow_routing_done] ||= [])
    done << step
    handle.get_window("second")&.close if (STEPS - done).empty?
  end

  # Builds "second" and its webview "side" beside the app's "main", with
  # the scripts App gives a webview, so "side"'s page can invoke.
  SECOND = Ractor.shareable_proc do |app|
    FixtureApp.background(app)
    Thread.current[:multiwindow_routing_key] = app.invoke_key
    handle = app.app_handle
    event_loop = handle.runtime_context.window_target
    native_window = Tokra::Native::Window.new(event_loop, "second")
    native_window.set_title("Tokra integration: multiwindow routing (second)")
    native_window.set_size(320.0, 240.0)
    window = Tokra::Window.new(label: "second", native: native_window, app_handle: handle)
    FixtureApp.keep_in_sight(window)
    handle.windows["second"] = window
    scripts = app.__send__(:initialization_scripts, "second", "side")
    native_webview = Tokra::Native::WebView.new_with_protocol(native_window, event_loop.create_proxy, "side", scripts)
    handle.webviews["side"] = Tokra::Webview.new(label: "side", native: native_webview, window:, app_handle: handle)
  end

  # Names the webview each tokra:// request came from.
  PROTOCOL = Ractor.shareable_proc do |context, _request|
    puts "PROTOCOL #{context.webview_label}"
    next Tokra::Response.ok(PAGE) unless context.webview_label == "side"

    Tokra::Response.ok(SIDE_PAGE.sub("INVOKE_KEY_LITERAL", JSON.generate(Thread.current[:multiwindow_routing_key])))
  end

  # Names the webview each page load happened in.
  PAGE_LOAD = Ractor.shareable_proc do |webview, payload|
    puts "PAGE #{webview.label} #{payload.finished? ? 'finished' : 'started'}"
    MultiwindowRoutingFixture.step(webview.app_handle, "page:#{webview.label}") if payload.finished?
  end

  # Names the webview that invoked whoami, and the transport it came by.
  WHOAMI = Ractor.shareable_proc do |invoke|
    next false unless invoke.command == "whoami"

    via = invoke.payload["via"]
    puts "INVOKE #{invoke.webview.label} #{via}"
    invoke.resolve(invoke.webview.label)
    MultiwindowRoutingFixture.step(invoke.webview.app_handle, "invoke:#{via}")
    true
  end
end

Tokra::Builder.default
  .title("Tokra integration: multiwindow routing")
  .size(320, 240)
  .register_uri_scheme_protocol("tokra", &MultiwindowRoutingFixture::PROTOCOL)
  .on_page_load(&MultiwindowRoutingFixture::PAGE_LOAD)
  .invoke_handler(&MultiwindowRoutingFixture::WHOAMI)
  .setup(&MultiwindowRoutingFixture::SECOND)
  .run do |handle, event|
    case event
    when Tokra::RunEvent::Ready then FixtureApp.keep_in_sight(handle.get_window("main"))
    when Tokra::RunEvent::WindowEvent
      case event.event
      when Tokra::WindowEvent::CloseRequested, Tokra::WindowEvent::Destroyed
        puts "EVENT #{event.label} #{event.event.class.name}"
        if event.label == "second" && event.event.is_a?(Tokra::WindowEvent::Destroyed)
          handle.get_window("main").close
        end
      end
    when Tokra::RunEvent::ExitRequested then puts "EVENT exit-requested #{event.code.inspect}"
    when Tokra::RunEvent::Exit then puts "EVENT exit"
    end
  end
