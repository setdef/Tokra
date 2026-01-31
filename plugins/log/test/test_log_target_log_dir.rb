# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/autorun"
require "tokra-log"
require "tmpdir"
require "pathname"

# Tests for LogDir target kind (Tauri parity).
class TestLogTargetKindLogDir < Minitest::Test
  def test_log_dir_uses_os_specific_path
    skip "TODO: TargetKind::LogDir not implemented"
  end

  def test_log_dir_creates_directory_if_missing
    skip "TODO: TargetKind::LogDir not implemented"
  end

  def test_log_dir_uses_app_name_as_filename
    skip "TODO: TargetKind::LogDir not implemented"
  end
end
