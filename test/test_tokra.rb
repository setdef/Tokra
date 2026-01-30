# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

class TestTokra < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Tokra::VERSION
  end

  def test_it_does_something_useful
    skip "Use TDD and get rid of me!"
  end
end
