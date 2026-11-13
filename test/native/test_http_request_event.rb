# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::Native::HttpRequestEvent
class TestNativeHttpRequestEvent < Minitest::Test
  def test_is_defined
    assert defined?(Tokra::Native::HttpRequestEvent), "HttpRequestEvent should be defined"
  end

  def test_new_accepts_all_fields
    event = Tokra::Native::HttpRequestEvent.new(
      "main",
      123,
      "POST",
      "tokra://localhost/api",
      [["Content-Type", "application/json"]],
      '{"key":"value"}',
      "tokra"
    )

    assert_kind_of Tokra::Native::HttpRequestEvent, event
  end

  def test_request_id_returns_integer
    event = Tokra::Native::HttpRequestEvent.new("main", 42, "GET", "tokra://localhost/", [], "", "tokra")

    assert_equal 42, event.request_id
  end

  def test_method_returns_http_verb
    event = Tokra::Native::HttpRequestEvent.new("main", 1, "DELETE", "tokra://localhost/resource", [], "", "tokra")

    assert_equal "DELETE", event.method
  end

  def test_uri_returns_full_uri
    event = Tokra::Native::HttpRequestEvent.new("main", 1, "GET", "tokra://localhost/path?query=1", [], "", "tokra")

    assert_equal "tokra://localhost/path?query=1", event.uri
  end

  def test_body_returns_request_body
    event = Tokra::Native::HttpRequestEvent.new("main", 1, "POST", "tokra://localhost/", [], "form=data", "tokra")

    assert_equal "form=data", event.body
  end

  def test_body_accepts_binary
    binary = "\x00\x01\x02\xFF".b

    event = Tokra::Native::HttpRequestEvent.new("main", 1, "POST", "tokra://localhost/", [], binary, "tokra")

    assert_equal binary, event.body
    assert_equal Encoding::ASCII_8BIT, event.body.encoding
  end

  # The name the protocol was registered under, which App routes on
  # (plan 067).
  def test_scheme_names_the_protocol_the_request_came_through
    event = Tokra::Native::HttpRequestEvent.new("main", 1, "GET", "second://localhost/", [], "", "Second")

    assert_equal "Second", event.scheme
  end
end
