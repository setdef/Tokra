# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Fixture for webview_rows_test.rb: real webviews built with the webview
# rows of Tokra::WebviewWindowBuilder (plan 052, 052e-1), each reporting
# what its page can see of its row.
#
# It prints, each from the hook that hears it:
#
#   AGENT agent <user agent>          "agent"'s navigator.userAgent
#   SCRIPTS frames main=<b> all=<b>   which scripts ran in "frames"'s page
#   FRAME frames main=<b> all=<b>     which ran in the iframe in that page
#   IMAGE nojs <path>                 the image "nojs"'s page asked for
#   EVENT exit-requested <code> | EVENT exit
#
# "agent" sets user_agent; "frames" adds a main-frame script and an
# all-frames script and opens an iframe; "nojs" disables JavaScript, so
# its page shows its noscript image where a page that ran scripts would
# write another. When every line above has come, the app exits.
#
#   bundle exec ruby test/integration/fixtures/webview_rows/app.rb

require_relative "../../support/fixture_app"

module WebviewRowsFixture
  # The user agent "agent" sends.
  AGENT = "TokraProbe/1.0 (webview rows)"

  # "main"'s page, which does nothing.
  MAIN_PAGE = "<!doctype html><meta charset=utf-8><title>rows</title><p>main</p>"

  # "agent"'s page: its user agent, once it loads.
  AGENT_PAGE = <<~HTML
    <!doctype html><meta charset=utf-8><title>agent</title><p>agent</p>
    <script>
      window.__TAURI__.core.invoke('agent', { agent: navigator.userAgent })
    </script>
  HTML

  # "frames"'s page: which of the two scripts ran here, and which in the
  # iframe, whose page posts its own answer to this one.
  FRAMES_PAGE = <<~HTML
    <!doctype html><meta charset=utf-8><title>frames</title><p>frames</p>
    <script>
      const main = { main: window.__mainOnly === true, all: window.__allFrames === true }
      addEventListener('message', (event) => {
        if (event.source !== document.querySelector('iframe').contentWindow) return
        window.__TAURI__.core.invoke('frames', { main, frame: event.data })
      })
    </script>
    <iframe src="frame.html"></iframe>
  HTML

  # The iframe's page, which posts which of the two scripts ran in it.
  FRAME_PAGE = <<~HTML
    <!doctype html><meta charset=utf-8><title>frame</title><p>frame</p>
    <script>
      parent.postMessage({ main: window.__mainOnly === true, all: window.__allFrames === true }, '*')
    </script>
  HTML

  # "nojs"'s page: with JavaScript it writes an image asking for js.png,
  # and without it shows its noscript image, which asks for nojs.png.
  NOJS_PAGE = <<~HTML
    <!doctype html><meta charset=utf-8><title>nojs</title><p>nojs</p>
    <script>document.write('<img src="js.png" alt="">')</script>
    <noscript><img src="nojs.png" alt=""></noscript>
  HTML

  # What must happen before the app exits.
  STEPS = %w[agent frames image].freeze

  # Records +step+ on the main thread and exits once every one of STEPS
  # has happened.
  def self.step(handle, step)
    done = (Thread.current[:webview_rows_done] ||= [])
    done << step
    handle.exit(0) if (STEPS - done).empty?
  end

  # A webview window of +label+ opening +path+, each 240 by 180, kept in
  # sight on macOS.
  def self.build(app, label, path)
    builder = FixtureApp.webview_window(app, label, Tokra::WebviewUrl::App.new(path)).inner_size(240, 180)
    yield builder
    FixtureApp.keep_in_sight(builder.build.window)
  end

  SETUP = Ractor.shareable_proc do |app|
    FixtureApp.background(app)
    FixtureApp.keep_in_sight(app.get_window("main"))
    WebviewRowsFixture.build(app, "agent", "agent.html") { |builder| builder.user_agent(WebviewRowsFixture::AGENT) }
    WebviewRowsFixture.build(app, "frames", "frames.html") do |builder|
      builder.initialization_script("window.__mainOnly = true")
        .initialization_script_for_all_frames("window.__allFrames = true")
    end
    WebviewRowsFixture.build(app, "nojs", "nojs.html", &:disable_javascript)
  end

  # Serves each window's page, and prints an image "nojs" asks for.
  PROTOCOL = Ractor.shareable_proc do |context, request|
    path = Ferro::Url::Url.parse(request.uri).path
    label = context.webview_label
    case path
    when "/agent.html" then Tokra::Response.ok(WebviewRowsFixture::AGENT_PAGE)
    when "/frames.html" then Tokra::Response.ok(WebviewRowsFixture::FRAMES_PAGE)
    when "/frame.html" then Tokra::Response.ok(WebviewRowsFixture::FRAME_PAGE)
    when "/nojs.html" then Tokra::Response.ok(WebviewRowsFixture::NOJS_PAGE)
    when "/js.png", "/nojs.png"
      puts "IMAGE #{label} #{path.delete_prefix('/')}"
      handle = context.app_handle
      handle.run_on_main_thread { WebviewRowsFixture.step(handle, "image") }
      Tokra::Response.new(status: 404, headers: {}, body: "")
    else Tokra::Response.ok(WebviewRowsFixture::MAIN_PAGE)
    end
  end

  COMMANDS = Ractor.shareable_proc do |invoke|
    handle = invoke.webview.app_handle
    case invoke.command
    when "agent"
      puts "AGENT #{invoke.webview.label} #{invoke.payload['agent']}"
      invoke.resolve(nil)
      WebviewRowsFixture.step(handle, "agent")
    when "frames"
      main, frame = invoke.payload.values_at("main", "frame")
      puts "SCRIPTS #{invoke.webview.label} main=#{main['main']} all=#{main['all']}"
      puts "FRAME #{invoke.webview.label} main=#{frame['main']} all=#{frame['all']}"
      invoke.resolve(nil)
      WebviewRowsFixture.step(handle, "frames")
    else next false
    end
    true
  end
end

app = Tokra::Builder.default
  .register_uri_scheme_protocol("tokra", &WebviewRowsFixture::PROTOCOL)
  .invoke_handler(&WebviewRowsFixture::COMMANDS)
  .setup(&WebviewRowsFixture::SETUP)
  .build(Tokra.generate_context)
app.run do |_handle, event|
  case event
  when Tokra::RunEvent::ExitRequested then puts "EVENT exit-requested #{event.code.inspect}"
  when Tokra::RunEvent::Exit then puts "EVENT exit"
  end
end
