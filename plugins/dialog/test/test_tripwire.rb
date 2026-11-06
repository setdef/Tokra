# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/dialog_test"

# The tripwire in support/dialog_test.rb stops a ferro-rfd dialog from
# showing in the test process. It lists the showing methods by name, so
# these tests keep that list whole. Nothing here calls a dialog method.
class TestTripwire < Minitest::Test
  include DialogTest

  def test_every_public_method_of_a_guarded_dialog_is_either_terminal_or_known_not_to_show
    DialogTest::GUARDED.each do |dialog|
      unknown = dialog.public_instance_methods(false) - DialogTest::TERMINAL - DialogTest::NON_SHOWING

      assert_empty unknown, "#{dialog} has public methods the tripwire does not know: add each to " \
        "DialogTest::TERMINAL if it shows a dialog, or to DialogTest::NON_SHOWING if not"
    end
  end

  def test_the_tripwire_is_prepended_on_each_guarded_dialog_and_covers_its_terminal_methods
    DialogTest::GUARDED.each do |dialog|
      guard = dialog.ancestors.first

      refute_equal dialog, guard, "#{dialog} has no tripwire prepended"
      assert_instance_of Module, guard, "#{dialog} has no tripwire prepended"
      terminal = DialogTest::TERMINAL & dialog.public_instance_methods(false)

      assert_equal terminal.sort, guard.instance_methods(false).sort, "#{dialog}'s tripwire misses a terminal method"
    end
  end

  def test_each_terminal_name_is_a_method_of_some_guarded_dialog
    present = DialogTest::GUARDED.flat_map { |dialog| dialog.public_instance_methods(false) }

    assert_empty DialogTest::TERMINAL - present, "DialogTest::TERMINAL names a method no guarded dialog has"
  end
end
