# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::Manager interface requirements.
class TestManager < Minitest::Test
  def test_resources_table_raises_not_implemented_for_bare_includer
    includer = Object.new
    includer.extend(Tokra::Manager)

    error = assert_raises(NotImplementedError) { includer.resources_table }
    assert_match(/resources_table/, error.message)
  end
end
