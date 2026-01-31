# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/autorun"
require "tokra-log"
require "stringio"

# Tests for per-target filtering.
class TestLogTargetFiltering < Minitest::Test
  def test_target_filter_blocks_matching_messages
    skip "TODO: Target#filter not implemented"
  end

  def test_target_filter_passes_non_matching_messages
    skip "TODO: Target#filter not implemented"
  end

  def test_multiple_filters_combine_with_and
    skip "TODO: Target#filter chaining not implemented"
  end
end
