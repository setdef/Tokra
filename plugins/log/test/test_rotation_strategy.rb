# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/autorun"
require "tokra-log"

# Tests for RotationStrategy Data classes (Tauri API parity).
#
# RotationStrategy controls how many rotated log files to keep.
# Maps to Ruby Logger's shift_age parameter.
class TestRotationStrategy < Minitest::Test
  RotationStrategy = Tokra::Plugins::Log::RotationStrategy

  def test_keep_all_is_data_class_with_no_fields
    keep_all = RotationStrategy::KeepAll.new

    assert_kind_of Data, keep_all
    assert_equal [], keep_all.members
  end

  def test_keep_one_is_data_class_with_no_fields
    keep_one = RotationStrategy::KeepOne.new

    assert_kind_of Data, keep_one
    assert_equal [], keep_one.members
  end

  def test_keep_some_is_data_class_with_count_field
    keep_some = RotationStrategy::KeepSome.new(count: 5)

    assert_kind_of Data, keep_some
    assert_equal [:count], keep_some.members
    assert_equal 5, keep_some.count
  end

  # to_shift_age: returns Ruby Logger shift_age value

  def test_keep_all_converts_to_daily
    assert_equal "daily", RotationStrategy::KeepAll.new.to_shift_age
  end

  def test_keep_one_converts_to_1
    assert_equal 1, RotationStrategy::KeepOne.new.to_shift_age
  end

  def test_keep_some_converts_to_count
    assert_equal 5, RotationStrategy::KeepSome.new(count: 5).to_shift_age
  end

  # Integration with Target

  def test_target_rotation_strategy_returns_self_for_chaining
    target = Tokra::Plugins::Log::Target.new(Pathname("/tmp/test.log"))

    result = target.rotation_strategy(RotationStrategy::KeepSome.new(count: 3))

    assert_same target, result
  end

  def test_rotation_strategy_is_used_by_to_logger
    require "minitest/mock"

    Dir.mktmpdir do |dir|
      log_path = Pathname(dir).join("app.log")
      target = Tokra::Plugins::Log::Target.new(log_path)
        .rotation_strategy(RotationStrategy::KeepSome.new(count: 5))
      builder = Tokra::Plugins::Log::Builder.new

      # Spy: capture the shift_age passed to TracingLogger
      captured_shift_age = nil
      original_new = Tokra::Plugins::Log::TracingLogger.method(:new)
      Tokra::Plugins::Log::TracingLogger.stub(:new, -> (path, shift_age = 0, shift_size = nil) {
        captured_shift_age = shift_age
        original_new.call(path, shift_age, shift_size)
      }) do
        target.to_logger(builder)
      end

      assert_equal 5, captured_shift_age
    end
  end
end
