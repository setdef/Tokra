# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "support/stub_native"

# A webview's page and its cookies, as Tauri's Webview reaches them
# (plan 052, 052e-2): url parses wry's answer as a URL or raises
# InvalidUrl, navigate and reload log wry's failure in the runtime's
# words, the cookie getters fail as the runtime's getters fail, and
# set_cookie and delete_cookie log theirs (webview/mod.rs:1662-1678,
# 2094-2164; tauri-runtime-wry lib.rs:1580-1616, 1700-1745, 3647-3656,
# 3758-3792). WebviewWindow sends all seven to its webview
# (webview_window.rs:2299-2311, 2445-2490).
class TestWebviewPage < Minitest::Test
  SEND = "runtime error: #{Tokra::Error::Runtime::FAILED_TO_SEND_MESSAGE}".freeze
  RECEIVE = "runtime error: #{Tokra::Error::Runtime::FAILED_TO_RECEIVE_MESSAGE}".freeze

  def app_url
    (Tokra::App.os_name == "windows") ? "http://tokra.localhost/" : "tokra://localhost/"
  end

  # Runs an app and calls the block on the main thread once it is ready,
  # with the main webview; +tasks+ TaskEvents follow, each running one
  # task another thread queued.
  def run_app(tasks: 0, &on_ready)
    StubNative.inject_event(Array.new(tasks) { Tokra::Native::TaskEvent.new })
    Tokra::Builder.default.run(native: StubNative) do |handle, event|
      on_ready&.call(handle.get_webview("main"), handle) if event.is_a?(Tokra::RunEvent::Ready)
    end
  end

  def session_cookie = Tokra::Cookie.new(name: "session", value: "abc", domain: "localhost", path: "/")

  def test_url_answers_the_pages_url_as_a_uri
    run_app do |webview|
      url = webview.url

      assert_kind_of URI::Generic, url
      assert_equal URI(app_url), url
    end
  end

  # Tauri parses wry's String with the url crate (webview/mod.rs:1662-1668),
  # which needs a scheme; WebKitGTK answers "" before a page has a URI
  # (wry webkitgtk/mod.rs:682-684).
  def test_url_without_a_scheme_raises_invalid_url_as_the_url_crate_refuses_it
    run_app do |webview|
      webview.native.current_url = ""
      error = assert_raises(Tokra::Error::InvalidUrl) { webview.url }

      assert_equal "invalid url: relative URL without a base", error.message
    end
  end

  def test_url_that_ruby_cannot_parse_raises_invalid_url
    run_app do |webview|
      webview.native.current_url = "http://exa mple.test/"

      assert_raises(Tokra::Error::InvalidUrl) { webview.url }
    end
  end

  # The runtime's Url getter maps wry's error to FailedToSendMessage
  # (lib.rs:3758-3765), and a closed webview's goes unanswered.
  def test_url_fails_as_the_runtimes_getter_fails
    run_app do |webview|
      webview.native.page_error = RuntimeError.new("no url")
      error = assert_raises(Tokra::Error::Runtime) { webview.url }

      assert_equal SEND, error.message
      webview.native.page_error = nil
      webview.native.close
      error = assert_raises(Tokra::Error::Runtime) { webview.url }

      assert_equal RECEIVE, error.message
    end
  end

  def test_navigate_loads_the_url_and_url_reads_it_back
    run_app do |webview|
      assert_nil webview.navigate(URI("https://tauri.app/about"))

      assert_equal ["https://tauri.app/about"], webview.native.navigations
      assert_equal URI("https://tauri.app/about"), webview.url
    end
  end

  def test_navigate_takes_only_a_uri
    run_app do |webview|
      error = assert_raises(TypeError) { webview.navigate("https://tauri.app") }

      assert_equal "wrong argument type String (expected URI::Generic)", error.message
      assert_empty webview.native.navigations
    end
  end

  # tauri-runtime-wry logs a failed load_url and returns Ok
  # (lib.rs:3647-3651).
  def test_navigate_logs_wrys_failure_in_the_runtimes_words
    run_app do |webview|
      webview.native.page_error = RuntimeError.new("refused")

      assert_output(nil, "failed to navigate to url https://tauri.app/: refused\n") do
        assert_nil webview.navigate(URI("https://tauri.app/"))
      end
    end
  end

  def test_reload_reloads_and_logs_wrys_failure
    run_app do |webview|
      assert_nil webview.reload
      assert_equal 1, webview.native.reloads
      webview.native.page_error = RuntimeError.new("gone")

      assert_output(nil, "failed to reload: gone\n") { webview.reload }
      assert_equal 1, webview.native.reloads
    end
  end

  def test_a_closed_webview_ignores_navigate_reload_and_the_cookie_setters
    run_app do |webview|
      webview.native.close

      assert_output(nil, "") do
        webview.navigate(URI("https://tauri.app/"))
        webview.reload
        webview.set_cookie(session_cookie)
        webview.delete_cookie(session_cookie)
      end
      assert_empty webview.native.navigations
      assert_equal 0, webview.native.reloads
    end
  end

  def test_a_cookie_set_is_read_back_and_a_cookie_deleted_is_gone
    run_app do |webview|
      other = Tokra::Cookie.new(name: "theme", value: "dark", domain: "tauri.app", path: "/")

      assert_nil webview.set_cookie(session_cookie)
      assert_nil webview.set_cookie(other)
      assert_equal [session_cookie, other], webview.cookies
      assert_equal [session_cookie], webview.cookies_for_url(URI("http://localhost/"))
      assert_equal ["http://localhost/"], webview.native.cookie_urls

      assert_nil webview.delete_cookie(session_cookie)
      assert_equal [other], webview.cookies
    end
  end

  # Every field crosses to the native webview and back as the cookie
  # crate holds it.
  def test_every_field_of_a_cookie_crosses_the_native_boundary
    expires = Tokra::Cookie::Expiration::DateTime.new(datetime: Time.at(1_800_000_000).utc)
    full = Tokra::Cookie.new(name: "n", value: "v", expires:, max_age: 60, domain: "localhost", path: "/a",
      secure: true, http_only: false, same_site: Tokra::Cookie::SameSite::Strict, partitioned: true)
    run_app do |webview|
      webview.set_cookie(full)

      stored = {
        name: "n",
        value: "v",
        expires: 1_800_000_000,
        max_age: 60,
        domain: "localhost",
        path: "/a",
        secure: true,
        http_only: false,
        same_site: "Strict",
        partitioned: true,
      }

      assert_equal [stored], webview.native.cookie_store
      assert_equal [full], webview.cookies
    end
  end

  def test_the_cookie_methods_take_only_their_types
    run_app do |webview|
      assert_raises(TypeError) { webview.set_cookie({ name: "a", value: "b" }) }
      assert_raises(TypeError) { webview.delete_cookie("a=b") }
      error = assert_raises(TypeError) { webview.cookies_for_url("http://localhost/") }

      assert_equal "wrong argument type String (expected URI::Generic)", error.message
      assert_empty webview.native.cookie_store
    end
  end

  # wry's cookie errors reach Tauri as FailedToSendMessage
  # (lib.rs:3768-3792); a closed webview's getter goes unanswered.
  def test_the_cookie_getters_fail_as_the_runtimes_getters_fail
    run_app do |webview|
      webview.native.page_error = RuntimeError.new("timed out waiting for cookies response")

      assert_equal SEND, assert_raises(Tokra::Error::Runtime) { webview.cookies }.message
      assert_equal SEND, assert_raises(Tokra::Error::Runtime) { webview.cookies_for_url(URI("http://localhost/")) }.message
      webview.native.page_error = nil
      webview.native.close

      assert_equal RECEIVE, assert_raises(Tokra::Error::Runtime) { webview.cookies }.message
      assert_equal RECEIVE, assert_raises(Tokra::Error::Runtime) { webview.cookies_for_url(URI("http://localhost/")) }.message
    end
  end

  # tauri-runtime-wry logs a failed set_cookie and delete_cookie
  # (lib.rs:3773-3783).
  def test_the_cookie_setters_log_wrys_failure_in_the_runtimes_words
    run_app do |webview|
      webview.native.page_error = RuntimeError.new("refused")

      assert_output(nil, "failed to set webview cookie: refused\n") { assert_nil webview.set_cookie(session_cookie) }
      assert_output(nil, "failed to delete webview cookie: refused\n") { assert_nil webview.delete_cookie(session_cookie) }
    end
  end

  # From another thread each getter asks the main thread and waits, as the
  # runtime's getters do (lib.rs:196-230).
  def test_the_cookies_another_thread_asks_for_are_read_on_the_main_thread
    asker = nil
    read_on = nil
    run_app(tasks: 1) do |webview|
      webview.set_cookie(session_cookie)
      native = webview.native
      native.define_singleton_method(:cookies) do
        read_on = Thread.current
        super()
      end
      asker = Thread.new { webview.cookies }
      Thread.pass until asker.status == "sleep"
    end

    assert_equal [session_cookie], asker.value
    assert_same Thread.current, read_on
  end

  def test_a_webview_window_sends_the_page_and_cookie_methods_to_its_webview
    run_app do |webview, handle|
      window = handle.get_webview_window("main")
      window.navigate(URI("https://tauri.app/"))
      window.reload
      window.set_cookie(session_cookie)

      assert_equal URI("https://tauri.app/"), window.url
      assert_equal ["https://tauri.app/"], webview.native.navigations
      assert_equal 1, webview.native.reloads
      assert_equal [session_cookie], window.cookies
      assert_equal [session_cookie], window.cookies_for_url(URI("http://localhost/"))
      window.delete_cookie(session_cookie)

      assert_empty window.cookies
    end
  end

  # Tauri's Url is always absolute, so a relative URI is refused on the
  # calling thread.
  def test_navigate_and_cookies_for_url_refuse_a_relative_uri
    run_app do |webview|
      error = assert_raises(ArgumentError) { webview.navigate(URI("/about")) }

      assert_equal "relative URL without a base", error.message
      assert_raises(ArgumentError) { webview.cookies_for_url(URI("localhost/")) }
      assert_empty webview.native.navigations
      assert_empty webview.native.cookie_urls
    end
  end

  # Whatever the native side refuses, a command logs it and the loop goes
  # on, from the main thread and from another (plan 052, Review fixes
  # 052e-2, item 1).
  def test_a_native_refusal_of_any_kind_is_logged_and_the_loop_goes_on
    after = false
    assert_output(nil, /\A(failed to set webview cookie: out of range\n){2}\z/) do
      run_app(tasks: 2) do |webview, handle|
        webview.native.page_error = RangeError.new("out of range")

        assert_nil webview.set_cookie(session_cookie)
        Thread.new do
          webview.set_cookie(session_cookie)
          handle.run_on_main_thread { after = true }
        end.join
      end
    end

    assert after, "the task queued after the refused one still ran"
  end
end
