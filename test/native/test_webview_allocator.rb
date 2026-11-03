# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tokra::Native::WebView is built only by new_with_protocol (plan 052,
# 052a-0). Without its allocator undefined, Class#new would answer an
# empty object whose every method raises.
class TestNativeWebViewAllocator < Minitest::Test
  def test_new_raises_because_the_allocator_is_undefined
    error = assert_raises(TypeError) { Tokra::Native::WebView.new }

    assert_equal "allocator undefined for Tokra::Native::WebView", error.message
  end
end
