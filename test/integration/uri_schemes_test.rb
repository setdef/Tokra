# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/real_app"

# Custom URI schemes the builder holds, in a real webview (plan 067). The
# window loads its page from second://, a synchronous handler, which
# serves the harness and takes its reports too, so a scheme wry never
# registered would leave no report at all. The page fetches from third://,
# an asynchronous handler that answers from another thread, and invokes a
# command, which the local-origin check lets through because the page's
# scheme is held (webview/mod.rs:1696-1722). Each handler names the
# webview that asked and the scheme its protocol was registered under.
#
# On macOS and Linux a custom scheme's page is <scheme>://localhost; on
# Windows WebView2 serves it from http://<scheme>.localhost, and wry hands
# the handler <scheme>://localhost either way (wry 0.54.1
# src/webview2/mod.rs:972-976, 1089-1093).
class UriSchemesTest < RealApp::TestCase
  WINDOWS = RUBY_PLATFORM.match?(/mswin|mingw|cygwin/)

  def setup
    super
    @run = self.class.fixture_run { RealApp.launch("uri_schemes") }
    assert_finished @run
  end

  def test_exits_cleanly_once_every_check_passed
    assert_equal 0, @run.status, @run.describe
  end

  def test_the_window_loads_its_page_from_the_second_scheme
    detail = check_detail(@run, "page from the second scheme")

    assert_equal (WINDOWS ? "http://second.localhost/" : "second://localhost/"), detail["page"]
    assert_equal({ "label" => "main", "scheme" => "second", "uri" => "second://localhost/whoami" }, detail["seen"])
  end

  def test_the_page_fetches_from_the_third_scheme_answered_from_another_thread
    detail = check_detail(@run, "fetch from the third scheme")

    assert_equal (WINDOWS ? "http://third.localhost/data.json" : "third://localhost/data.json"), detail["url"]
    assert_equal 200, detail["status"]
    assert_equal({ "label" => "main", "scheme" => "third", "uri" => "third://localhost/data.json", "thread" => "other" },
      detail["seen"])
  end

  def test_a_page_from_a_held_scheme_may_invoke
    assert_equal({ "reply" => "main" }, check_detail(@run, "invoke from the second scheme"))
  end
end
