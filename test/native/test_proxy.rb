# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for the real Tokra::Native::Proxy response path.
#
# Before Plan 016, respond took its body as a Rust String, so magnus
# rejected any body that was not UTF-8 with EncodingError while converting
# the arguments, before the request could be answered.
class TestNativeProxy < Minitest::Test
  PNG = File.binread(File.expand_path("../fixtures/2x2.png", __dir__))

  def setup
    skip "Requires display server" if ENV["CI"] && !ENV["DISPLAY"]
    @proxy = Tokra::Native::EventLoop.new.create_proxy
  end

  def test_respond_accepts_a_binary_body
    refute PNG.dup.force_encoding(Encoding::UTF_8).valid_encoding?,
      "the fixture must not be valid UTF-8 for this test to mean anything"

    # No request 0 is pending, so the call fails, but only after the body
    # converted: the error is the missing request, not the encoding.
    error = assert_raises(RuntimeError) { @proxy.respond(0, 200, [], PNG.b) }
    assert_equal "No pending request with id 0", error.message
  end

  def test_respond_accepts_a_binary_body_tagged_utf8
    error = assert_raises(RuntimeError) { @proxy.respond(0, 200, [], PNG.dup.force_encoding(Encoding::UTF_8)) }
    assert_equal "No pending request with id 0", error.message
  end

  def test_drop_response_of_an_unknown_request_is_a_no_op
    assert_nil @proxy.drop_response(0), "dropping is idempotent"
  end
end
