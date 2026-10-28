# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tauri's unit enums hold only their variants; none of Data's builders
# makes a value outside them.
class TestClosedEnum < Minitest::Test
  ENUMS = [
    Tokra::Theme,
    Tokra::CursorIcon,
    Tokra::ResizeDirection,
    Tokra::UserAttentionType,
    Tokra::Menu::NativeIcon,
    # ActivationPolicy exists only on macOS, as Tauri's cfg has it
    # (plan 029), so it is checked only where it is defined.
    *(Tokra.const_defined?(:ActivationPolicy) ? [Tokra.const_get(:ActivationPolicy)] : []),
].freeze

  def test_new_and_brackets_are_private
    ENUMS.each do |klass|
      assert_raises(NoMethodError, klass.name) { klass.new(name: "Bogus") }
      assert_raises(NoMethodError, klass.name) { klass[name: "Bogus"] }
      assert_raises(NoMethodError, klass.name) { klass["Bogus"] }
    end
  end

  def test_with_answers_only_a_constant_of_the_class
    ENUMS.each do |klass|
      first, second = klass.constants.map { |name| klass.const_get(name, false) }.grep(klass).first(2)
      assert_same second, first.with(name: second.name), klass.name
      assert_same first, first.with, klass.name
      error = assert_raises(ArgumentError, klass.name) { first.with(name: "Bogus") }
      assert_equal %(no #{klass.name} has {name: "Bogus"}), error.message
    end
  end
end
