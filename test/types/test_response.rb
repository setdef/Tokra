# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::Response type and factory methods.
class TestResponse < Minitest::Test
  def test_stores_status_headers_body
    response = Tokra::Response.new(status: 200, headers: { "x-foo" => "bar" }, body: "OK")

    assert_equal 200, response.status
    assert_equal({ "x-foo" => "bar" }, response.headers)
    assert_equal "OK", response.body
  end

  def test_ok_factory_creates_200_with_html_content_type
    response = Tokra::Response.ok("<h1>Hello</h1>")

    assert_equal 200, response.status
    assert_equal "text/html", response.headers["content-type"]
    assert_equal "<h1>Hello</h1>", response.body
  end

  def test_ok_factory_accepts_custom_content_type
    response = Tokra::Response.ok('{"ok":true}', content_type: "application/json")

    assert_equal 200, response.status
    assert_equal "application/json", response.headers["content-type"]
  end

  def test_not_found_factory_creates_404
    response = Tokra::Response.not_found

    assert_equal 404, response.status
    assert_equal "text/plain", response.headers["content-type"]
    assert_equal "Not Found", response.body
  end

  def test_not_found_factory_accepts_custom_message
    response = Tokra::Response.not_found("Page missing")

    assert_equal 404, response.status
    assert_equal "Page missing", response.body
  end

  def test_error_factory_creates_custom_status
    response = Tokra::Response.error(500, "Internal error")

    assert_equal 500, response.status
    assert_equal "text/plain", response.headers["content-type"]
    assert_equal "Internal error", response.body
  end
end
