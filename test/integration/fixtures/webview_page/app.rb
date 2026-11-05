# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Fixture for webview_page_test.rb: a real webview that navigates to a page
# this app serves over HTTP on localhost, reads its URL, reloads it, and
# sets, reads, and deletes cookies there (plan 052, 052e-2). Every call is
# made from the page-load hook, which runs from the event loop, or from a
# thread that asks the main thread, so the platform's wait for its cookie
# store runs inside the loop's callback, where plan 052's decision e2-1
# says it is safe.
#
# It prints, each from the hook or server that sees it:
#
#   SERVER <port>                        the port the HTTP server took
#   REQUEST <path> cookie=<names>        each request, its cookies by name, sorted, or -
#   URL nav <url>                        Webview#url once the HTTP page loads
#   COOKIES for-url <names>              cookies_for_url's, by name, sorted
#   READS <label> <n>                    how many reads a cookie write took to show
#   COOKIES all <names>                  cookies after set_cookie
#   RELOADED                             the page loaded again after reload
#   COOKIES after-delete <names>         cookies_for_url after delete_cookie
#   COOKIES thread <names>               cookies_for_url, asked from another thread
#   EVENT exit-requested <code> | EVENT exit
#
#   bundle exec ruby test/integration/fixtures/webview_page/app.rb

require_relative "../../support/fixture_app"
require "fileutils"
require "socket"
require "tmpdir"

$stdout.sync = true

module WebviewPageFixture
  # The HTTP server on localhost, every address it resolves to, on one
  # port, so the webview reaches it whichever it tries.
  SOCKETS = Socket.tcp_server_sockets("localhost", 0)
  PORT = SOCKETS.first.local_address.ip_port

  # The page the server answers, which sets the cookie "page".
  PAGE = "<!doctype html><meta charset=utf-8><title>page</title><p>page</p>"

  # Where "nav" goes, and the URL its cookies are asked for.
  FIRST = "http://localhost:#{PORT}/first".freeze
  ORIGIN = "http://localhost:#{PORT}/".freeze

  # "nav"'s data directory, made fresh for this run and removed after it.
  # On Linux the app's protocols are registered on a directory's context
  # by its first webview, and "main" is the first in the default one; an
  # incognito webview has a context of its own, so built there after
  # "main" it would have no tokra:// to load index.html from
  # (WebviewWindowBuilder#data_directory).
  DATA_DIRECTORY = Dir.mktmpdir("tokra-webview-page").freeze

  # The cookie Ruby sets.
  APP_COOKIE = Tokra::Cookie.new(name: "app", value: "from-ruby", domain: "localhost", path: "/")

  # Answers each request with PAGE, each connection on its own thread,
  # since WebKit may open one it sends nothing on, and prints its path and
  # the names of the cookies it carried.
  def self.serve
    Thread.new do
      Socket.accept_loop(SOCKETS) { |client, _| Thread.new(client) { |connection| answer(connection) } }
    end
  end

  def self.answer(client)
    request = client.gets or return
    headers = {}
    while (line = client.gets) && line != "\r\n"
      name, value = line.chomp.split(": ", 2)
      headers[name.downcase] = value
    end
    names = headers.fetch("cookie", "").split("; ").map { |pair| pair.split("=", 2).first }.sort
    puts "REQUEST #{request.split[1]} cookie=#{names.empty? ? '-' : names.join(',')}"
    client.write("HTTP/1.1 200 OK\r\ncontent-type: text/html; charset=utf-8\r\n" \
      "set-cookie: page=from-server; Path=/\r\ncontent-length: #{PAGE.bytesize}\r\n" \
      "connection: close\r\n\r\n#{PAGE}")
  rescue SystemCallError, IOError
    nil
  ensure
    client.close
  end

  def self.names(cookies) = cookies.map(&:name).sort.join(",")

  # How many times a read after a cookie write is tried before its
  # answer counts. On Windows wry hands WebView2 each write and returns,
  # with no completion (webview2/mod.rs:1656-1675), and WebView2 documents
  # no order between AddOrUpdateCookie or DeleteCookie and a later
  # GetCookies, so a read right after a write may not see it. Nothing in
  # wry or WebView2 gives a principled bound; 50 is a margin. Each read
  # waits for WebView2's answer, so it counts round trips to its browser
  # process, not time. Elsewhere the write is done when its call returns,
  # and the first read must see it.
  READS = RUBY_PLATFORM.match?(/mswin|mingw|cygwin/) ? 50 : 1

  # Calls +read+ until the block holds of its answer, at most READS
  # times, prints how many it took after +label+, and answers the last.
  def self.settle(label, read)
    answer = nil
    tries = (1..READS).find do
      answer = read.call
      yield answer
    end
    puts "READS #{label} #{tries || 'gave-up'}"
    answer
  end

  # What "nav" does each time a page finishes loading, on the main thread.
  def self.loaded(webview)
    loads = (Thread.current[:webview_page_loads] ||= 0)
    Thread.current[:webview_page_loads] = loads + 1
    case loads
    when 0 then webview.navigate(Ferro::Url::Url.parse(FIRST))
    when 1 then first_load(webview)
    when 2 then reloaded(webview)
    end
  end

  # The HTTP page's first load: its URL, the cookie the server set, one
  # Ruby sets, and a reload, whose request carries both.
  def self.first_load(webview)
    puts "URL nav #{webview.url}"
    puts "COOKIES for-url #{names(webview.cookies_for_url(Ferro::Url::Url.parse(ORIGIN)))}"
    webview.set_cookie(APP_COOKIE)
    stored = settle("all", -> { webview.cookies.select { |cookie| cookie.domain == "localhost" } }) do |cookies|
      cookies.any? { |cookie| cookie.name == "app" }
    end
    puts "COOKIES all #{names(stored)}"
    webview.reload
  end

  # After the reload: Ruby's cookie deleted, then read again from another
  # thread, which waits for the main thread to answer.
  def self.reloaded(webview)
    puts "RELOADED"
    webview.delete_cookie(APP_COOKIE)
    left = settle("after-delete", -> { webview.cookies_for_url(Ferro::Url::Url.parse(ORIGIN)) }) do |cookies|
      cookies.none? { |cookie| cookie.name == "app" }
    end
    puts "COOKIES after-delete #{names(left)}"
    handle = webview.app_handle
    Thread.new do
      puts "COOKIES thread #{names(webview.cookies_for_url(Ferro::Url::Url.parse(ORIGIN)))}"
      handle.run_on_main_thread { handle.exit(0) }
    end
  end

  SETUP = Ractor.shareable_proc do |app|
    FixtureApp.background(app)
    FixtureApp.keep_in_sight(app.get_window("main"))
    # Incognito, so the cookies stay in memory and never reach the disk.
    builder = FixtureApp.webview_window(app, "nav", Tokra::WebviewUrl::App.new("index.html"))
      .inner_size(240, 180).incognito(true).data_directory(WebviewPageFixture::DATA_DIRECTORY)
    FixtureApp.keep_in_sight(builder.build.window)
  end

  PAGE_LOAD = Ractor.shareable_proc do |webview, payload|
    WebviewPageFixture.loaded(webview) if webview.label == "nav" && payload.finished?
  end

  PROTOCOL = Ractor.shareable_proc do |_context, _request|
    Tokra::Response.ok("<!doctype html><meta charset=utf-8><title>app</title><p>app</p>")
  end
end

at_exit { FileUtils.rm_rf(WebviewPageFixture::DATA_DIRECTORY) }

puts "SERVER #{WebviewPageFixture::PORT}"
WebviewPageFixture.serve

app = Tokra::Builder.default
  .register_uri_scheme_protocol("tokra", &WebviewPageFixture::PROTOCOL)
  .on_page_load(&WebviewPageFixture::PAGE_LOAD)
  .setup(&WebviewPageFixture::SETUP)
  .build(Tokra.generate_context)
app.run do |_handle, event|
  case event
  when Tokra::RunEvent::ExitRequested then puts "EVENT exit-requested #{event.code.inspect}"
  when Tokra::RunEvent::Exit then puts "EVENT exit"
  end
end
