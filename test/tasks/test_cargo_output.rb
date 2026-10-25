# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../../tasks/cargo_output"

# Tests the runner that fails a build step on any rustc, Clippy, or Cargo
# warning, using small Ruby scripts in place of cargo.
class TestCargoOutput < Minitest::Test
  private def run_script(source)
    out = StringIO.new
    output = CargoOutput.run!(RbConfig.ruby, "-e", source, out:)
    [output, out.string]
  end

  def test_clean_output_passes_and_is_echoed
    output, echoed = run_script(%(puts "   Compiling tokra v0.1.0"))

    assert_includes output, "Compiling tokra"
    assert_includes echoed, "Compiling tokra"
  end

  def test_a_rustc_warning_fails_even_when_the_command_succeeds
    error = assert_raises(CargoOutput::Failure) { run_script(%(puts "warning: unused variable: `x`")) }

    assert_includes error.message, "warning: unused variable"
  end

  # The case that got through: an unknown lint in a [lints] table, which
  # -D warnings does not turn into an error.
  def test_a_coded_warning_fails
    error = assert_raises(CargoOutput::Failure) do
      run_script(%(warn "warning[E0602]: unknown lint: `clippy::unsafe_code`"))
    end

    assert_includes error.message, "E0602"
  end

  def test_a_failing_command_fails
    error = assert_raises(CargoOutput::Failure) { run_script("exit 3") }

    assert_includes error.message, "failed"
  end

  # What cargo prints with CARGO_TERM_COLOR=always, which CI sets.
  def test_a_colored_warning_fails
    error = assert_raises(CargoOutput::Failure) do
      run_script(%(puts "\\e[1m\\e[33mwarning\\e[0m\\e[1m: unused variable: `x`\\e[0m"))
    end

    assert_includes error.message, "warning: unused variable: `x`"
  end

  def test_only_lines_that_start_a_warning_count
    text = "note: the `unknown_lints` lint ignores warnings\n   = warning: indented\nwarnings: 0\nwarning: real\n"

    assert_equal ["warning: real"], CargoOutput.warnings(text)
  end
end
