# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/autorun"
require "tokra-log"
require "tmpdir"
require "pathname"

# Tests for RotationStrategy (Tauri parity).
class TestLogRotationStrategy < Minitest::Test
  def test_keep_one_removes_old_log
    skip "TODO: RotationStrategy::KeepOne not implemented"
  end

  def test_keep_all_preserves_all_logs
    skip "TODO: RotationStrategy::KeepAll not implemented"
  end

  def test_keep_some_limits_log_count
    skip "TODO: RotationStrategy::KeepSome not implemented"
  end
end
