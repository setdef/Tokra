# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/native_event_loop"

# Native::WebView's page and cookie calls against the real extension
# (plan 052, 052e-2). A webview not yet filled, or closed, answers nil to
# the getters and ignores the rest, as Tauri's runtime ignores a message
# for a webview it no longer holds (tauri-runtime-wry lib.rs:3600-3614);
# an open one answers its URL as a String; and a cookie Hash in the wrong
# shape raises before the webview is touched. The cookie store itself is
# exercised in a running loop, by webview_page_test.rb.
class TestNativeWebviewPage < Minitest::Test
  MACOS = RbConfig::CONFIG["host_os"].include?("darwin")
  LINUX = RbConfig::CONFIG["host_os"].include?("linux")

  # The webview attributes a page at Tokra's URL opens with.
  PAGE = { url: "tokra://localhost/", initialization_scripts: [] }.freeze

  # A cookie Hash as Tokra::Cookie#native_fields makes one.
  FIELDS = {
    name: "n",
    value: "v",
    expires: nil,
    max_age: nil,
    domain: "localhost",
    path: "/",
    secure: nil,
    http_only: nil,
    same_site: nil,
    partitioned: nil,
  }.freeze

  def setup
    reason = NativeEventLoop.unavailable_reason
    skip reason if reason

    @event_loop = NativeEventLoop.shared
    @proxy = @event_loop.create_proxy
  end

  # Asks +webview+ each page and cookie call, all of which a webview
  # without a wry webview answers with nil.
  def assert_answers_nothing(webview)
    assert_nil webview.url
    assert_nil webview.cookies
    assert_nil webview.cookies_for_url("http://localhost/")
    assert_nil webview.navigate("http://localhost/")
    assert_nil webview.reload
    assert_nil webview.set_cookie(FIELDS)
    assert_nil webview.delete_cookie(FIELDS)
  end

  def test_an_empty_or_closed_webview_answers_nil_and_ignores_the_rest
    window = Tokra::Native::Window.new(@event_loop, "page-closed")
    webview = Tokra::Native::WebView.empty(@proxy)
    assert_answers_nothing(webview)
    webview.open(window, @proxy, "page-closed", PAGE)
    webview.close
    assert_answers_nothing(webview)
  ensure
    window&.close
  end

  # An open webview answers the URL it loads. WebView2 may answer
  # about:blank until its first navigation starts, and builds Tokra's URLs
  # in its own form, so off macOS and Linux only the type is checked.
  def test_an_open_webview_answers_its_url_as_a_string
    window = Tokra::Native::Window.new(@event_loop, "page-url")
    webview = Tokra::Native::WebView.empty(@proxy)
    webview.open(window, @proxy, "page-url", PAGE)

    if MACOS || LINUX
      assert_equal "tokra://localhost/", webview.url
    else
      assert_kind_of String, webview.url
    end
  ensure
    webview&.close
    window&.close
  end

  def test_a_cookie_hash_in_the_wrong_shape_raises_before_the_webview_is_touched
    webview = Tokra::Native::WebView.empty(@proxy)
    {
      FIELDS.except(:name) => KeyError,
      FIELDS.merge(value: 1) => TypeError,
      FIELDS.merge(path: :root) => TypeError,
      FIELDS.merge(same_site: "Loose") => ArgumentError,
      FIELDS.merge(expires: "Forever") => ArgumentError,
      FIELDS.merge(expires: 2 ** 80) => RangeError,
      FIELDS.merge(expires: 10 ** 15) => RangeError,
    }.each do |fields, error|
      assert_raises(error, fields.inspect) { webview.set_cookie(fields) }
      assert_raises(error, fields.inspect) { webview.delete_cookie(fields) }
    end
  end

  # Where wry panics on a cookie the platform cannot hold, the webview
  # raises wry's message, and stays usable (wkwebview/mod.rs:1082-1083;
  # webkitgtk/mod.rs:981-983). Tauri panics there.
  def test_a_cookie_wry_panics_on_raises_its_message_and_the_webview_goes_on
    skip "only macOS and Linux panic on these cookies" unless MACOS || LINUX
    window = Tokra::Native::Window.new(@event_loop, "page-panic")
    webview = Tokra::Native::WebView.empty(@proxy)
    webview.open(window, @proxy, "page-panic", PAGE)
    fields = MACOS ? FIELDS.merge(name: "") : FIELDS.merge(expires: -70_000_000_000)

    message = MACOS ? "failed to create wkwebview cookie, report this as bug to `wry`" : "called `Option::unwrap()` on a `None` value"
    # Rust's panic hook writes to file descriptor 2, which this captures.
    _, stderr = capture_subprocess_io do
      assert_equal message, assert_raises(RuntimeError) { webview.set_cookie(fields) }.message
      assert_equal message, assert_raises(RuntimeError) { webview.delete_cookie(fields) }.message
    end

    assert_includes stderr, message, "the panic is still reported"
    assert_kind_of String, webview.url
  ensure
    webview&.close
    window&.close
  end

  # A cookie set in the real store reads back with every field the
  # platform keeps, as wry reads each (wkwebview/mod.rs:977-1017;
  # webview2/mod.rs:1501-1555; webkitgtk/mod.rs:926-967). The wait for the
  # store runs here outside any loop, as before App#run. The webview is
  # incognito, so its cookies stay in memory and never reach the disk.
  #
  # The cookie gives secure and leaves http_only unset, which reads back
  # false everywhere: on macOS wry writes a false flag as the string FALSE
  # (wkwebview/mod.rs:1053-1068), which NSHTTPCookie counts as set.
  def test_a_cookie_set_reads_back_from_the_real_store_and_deletes
    window = Tokra::Native::Window.new(@event_loop, "page-store")
    webview = Tokra::Native::WebView.empty(@proxy)
    webview.open(window, @proxy, "page-store", PAGE.merge(incognito: true))
    # Within the 400 days WebKit caps a cookie's life at (RFC 6265bis).
    expires = Time.now.to_i + (30 * 86_400)
    sent = FIELDS.merge(name: "store", value: "kept", expires:, secure: true, same_site: "Strict")

    elsewhere = FIELDS.merge(name: "elsewhere", domain: "example.test")
    webview.set_cookie(sent)
    webview.set_cookie(elsewhere)
    read = webview.cookies.find { |cookie| cookie[:name] == "store" }

    assert_equal sent.merge(http_only: false), read
    assert_equal ["elsewhere", "store"], webview.cookies.map { |cookie| cookie[:name] }.sort
    assert_equal ["store"], webview.cookies_for_url("http://localhost/").map { |cookie| cookie[:name] },
      "cookies_for_url leaves out another domain's cookie"
    webview.delete_cookie(elsewhere)
    webview.delete_cookie(sent)

    assert_nil webview.cookies.find { |cookie| cookie[:name] == "store" }
  ensure
    webview&.close
    window&.close
  end
end
