# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/native_event_loop"

# Native::WebView#open refuses a bad webview row before it builds
# anything, against the real extension (plan 052, 052e-1): a proxy of a
# scheme tauri-runtime-wry's parse_proxy_url refuses raises its error
# (lib.rs:4301-4316; tauri-runtime lib.rs:161-162), a policy or style no
# variant names raises ArgumentError, and on macOS a data store byte out of
# range raises RangeError. The webview, never opened, opens afterwards.
class TestNativeWebviewOpenErrors < Minitest::Test
  MACOS = RbConfig::CONFIG["host_os"].include?("darwin")
  WINDOWS = RbConfig::CONFIG["host_os"].match?(/mswin|mingw|cygwin/)

  # The webview attributes a page at Tokra's URL opens with.
  PAGE = { url: "tokra://localhost/", initialization_scripts: [] }.freeze

  def setup
    reason = NativeEventLoop.unavailable_reason
    skip reason if reason

    @event_loop = NativeEventLoop.shared
    @proxy = @event_loop.create_proxy
  end

  # Opens a webview with +rows+, which must raise +error_class+, and then
  # with none, which must open it. Answers the error.
  def refused(label, rows, error_class)
    window = Tokra::Native::Window.new(@event_loop, label)
    webview = Tokra::Native::WebView.empty(@proxy)
    error = assert_raises(error_class) { webview.open(window, @proxy, label, PAGE.merge(rows)) }
    assert_nil webview.open(window, @proxy, label, PAGE), "a refused webview was never opened, so it opens"
    error
  ensure
    webview&.close
    window&.close
  end

  def test_a_proxy_of_another_scheme_raises_runtime_error_invalid_proxy_url
    error = refused("errors-proxy", { proxy_url: ["https", "proxy.test", "3128"] }, RuntimeError)

    assert_equal "Invalid proxy url", error.message
  end

  def test_a_policy_no_variant_names_raises_argument_error
    error = refused("errors-policy", { background_throttling: "Off" }, ArgumentError)

    assert_equal "unknown background throttling policy: Off", error.message
  end

  def test_on_windows_a_scroll_bar_style_no_variant_names_raises_argument_error
    skip "only Windows reads the scroll bar style" unless WINDOWS
    error = refused("errors-style", { scroll_bar_style: "Thin" }, ArgumentError)

    assert_equal "unknown scroll bar style: Thin", error.message
  end

  def test_on_macos_a_data_store_byte_out_of_range_raises_range_error
    skip "only macOS reads the data store identifier" unless MACOS
    refused("errors-store-high", { data_store_identifier: ([0] * 15) + [256] }, RangeError)
    refused("errors-store-low", { data_store_identifier: [-1] + ([0] * 15) }, RangeError)
  end
end
