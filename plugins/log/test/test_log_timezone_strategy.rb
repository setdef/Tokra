# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/autorun"
require "tokra-log"
require "stringio"

# Tests for TimezoneStrategy (Tauri parity).
class TestLogTimezoneStrategy < Minitest::Test
  def test_use_utc_formats_timestamps_in_utc
    skip "TODO: TimezoneStrategy::UseUtc not implemented"
  end

  def test_use_local_formats_timestamps_in_local
    skip "TODO: TimezoneStrategy::UseLocal not implemented"
  end
end
