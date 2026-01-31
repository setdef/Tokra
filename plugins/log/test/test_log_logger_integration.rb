# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/autorun"
require "tokra-log"
require "stringio"

# Tests for stdlib Logger integration.
class TestLogLoggerIntegration < Minitest::Test
  def test_formatter_customizes_output_format
    skip "TODO: formatter= not exposed"
  end

  def test_progname_appears_in_log_entries
    skip "TODO: progname= not exposed"
  end

  def test_datetime_format_customizes_timestamp
    skip "TODO: datetime_format= not exposed"
  end

  def test_add_method_with_all_arguments
    skip "TODO: add(level, message, progname) not implemented"
  end

  def test_shift_operator_writes_raw_message
    skip "TODO: << operator not implemented"
  end
end
