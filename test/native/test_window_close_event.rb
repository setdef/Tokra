# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::Native::WindowCloseEvent
class TestNativeWindowCloseEvent < Minitest::Test
  def test_is_defined
    assert defined?(Tokra::Native::WindowCloseEvent), "WindowCloseEvent should be defined"
  end

  def test_new_requires_no_arguments
    event = Tokra::Native::WindowCloseEvent.new

    assert_kind_of Tokra::Native::WindowCloseEvent, event
  end
end
