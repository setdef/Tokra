# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/autorun"
require "tokra-log"

# Tests for Log::Target configuration class.
class TestLogTarget < Minitest::Test
  def test_raises_argument_error_when_shift_age_passed_with_stdout
    assert_raises(ArgumentError) do
      Tokra::Plugins::Log::Target.new($stdout, shift_age: 3)
    end
  end

  def test_raises_argument_error_when_shift_size_passed_with_stderr
    assert_raises(ArgumentError) do
      Tokra::Plugins::Log::Target.new($stderr, shift_size: 1024)
    end
  end

  def test_accepts_rotation_params_with_pathname
    target = Tokra::Plugins::Log::Target.new(
      Pathname("logs/app.log"),
      shift_age: 3,
      shift_size: 10_485_760
    )
    assert_instance_of Tokra::Plugins::Log::Target, target
  end

  def test_accepts_stdout_without_rotation_params
    target = Tokra::Plugins::Log::Target.new($stdout)
    assert_instance_of Tokra::Plugins::Log::Target, target
  end
end
