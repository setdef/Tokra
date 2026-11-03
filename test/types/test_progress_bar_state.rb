# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# The window plugin's ProgressBarState (window/mod.rs:2209-2221) and its
# ProgressBarStatus (tauri-runtime src/lib.rs:51-65), read as their
# derived Deserialize reads serde_json's Value.
class TestProgressBarState < Minitest::Test
  private def mismatch(&)
    assert_raises(Tokra::Ipc::CommandItem::Mismatch, &).message
  end

  STATUS_NAMES = "one of `none`, `normal`, `indeterminate`, `paused`, `error`"

  # rename_all = "camelCase": each name with its first letter lowercased.
  def test_a_status_reads_its_camel_case_name
    {
      "none" => Tokra::ProgressBarStatus::None,
      "normal" => Tokra::ProgressBarStatus::Normal,
      "indeterminate" => Tokra::ProgressBarStatus::Indeterminate,
      "paused" => Tokra::ProgressBarStatus::Paused,
      "error" => Tokra::ProgressBarStatus::Error,
    }.each { |name, status| assert_same status, Tokra::ProgressBarStatus.deserialize(name) }
    assert_same Tokra::ProgressBarStatus::Error, Tokra::ProgressBarStatus.deserialize({ "error" => nil })
    assert_equal "unknown variant `Normal`, expected #{STATUS_NAMES}", mismatch { Tokra::ProgressBarStatus.deserialize("Normal") }
  end

  # Both fields are Options, read from a map whose other keys are ignored
  # or from a sequence.
  def test_a_state_reads_a_map_or_a_sequence
    assert_equal Tokra::ProgressBarState.new(status: Tokra::ProgressBarStatus::Normal, progress: 40),
      Tokra::ProgressBarState.deserialize({ "status" => "normal", "progress" => 40, "other" => 1 })
    assert_equal Tokra::ProgressBarState.new(status: Tokra::ProgressBarStatus::Paused, progress: 10),
      Tokra::ProgressBarState.deserialize(["paused", 10])
    assert_equal Tokra::ProgressBarState.new, Tokra::ProgressBarState.deserialize({})
    assert_equal Tokra::ProgressBarState.new, Tokra::ProgressBarState.deserialize({ "status" => nil, "progress" => nil })
    assert_equal Tokra::ProgressBarState.new(progress: 18_446_744_073_709_551_615),
      Tokra::ProgressBarState.deserialize({ "progress" => 18_446_744_073_709_551_615 })
  end

  # progress is a u64.
  def test_a_state_rejects_in_serdes_words
    assert_equal "invalid value: integer `-1`, expected u64", mismatch { Tokra::ProgressBarState.deserialize({ "progress" => -1 }) }
    assert_equal "invalid type: floating point `1.5`, expected u64",
      mismatch { Tokra::ProgressBarState.deserialize({ "progress" => 1.5 }) }
    assert_equal "unknown variant `Paused`, expected #{STATUS_NAMES}",
      mismatch { Tokra::ProgressBarState.deserialize({ "status" => "Paused" }) }
    assert_equal "invalid length 1, expected struct ProgressBarState with 2 elements",
      mismatch { Tokra::ProgressBarState.deserialize(["none"]) }
    assert_equal "invalid type: integer `1`, expected struct ProgressBarState", mismatch { Tokra::ProgressBarState.deserialize(1) }
  end
end
