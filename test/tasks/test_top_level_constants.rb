# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tokra::Process mirrors tauri::process, so inside module Tokra a bare
# Process names it, not Ruby's module (plan 039, decision 8). RuboCop's
# Lint/ConstantResolution refuses one in lib/ and every plugin's lib/;
# RuboCop does not read RBS, so this test refuses one in the signatures.
class TestTopLevelConstants < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  # A Process with no namespace before it: not ::Process, not
  # Tokra::Process, and not part of a longer name.
  BARE = /(?<![\w:])Process(?!\w)/

  # The bare Process references in +source+, an RBS file's text, as
  # "line: text", skipping comment lines.
  private def bare_references(source)
    source.each_line.with_index(1).filter_map do |line, number|
      next if line.lstrip.start_with?("#")

      "#{number}: #{line.strip}" if line.match?(BARE)
    end
  end

  def test_the_check_finds_a_bare_process_and_nothing_else
    assert_equal ["1: def pid: (Process::Status s) -> void"], bare_references("def pid: (Process::Status s) -> void\n")
    assert_empty bare_references("# Process\ndef pid: (::Process::Status s) -> Tokra::Process::StartingBinary\n")
    assert_empty bare_references("def run: (Processor p, MyProcess q) -> void\n")
  end

  def test_signatures_name_ruby_s_process_and_tokra_s_from_the_top
    files = Dir.chdir(ROOT) { `git ls-files -- "sig/*.rbs" "sig/**/*.rbs" "plugins/*/sig/**/*.rbs"`.split("\n") }
    files = files.uniq.reject { |path| path == "sig/tokra/process.rbs" }
    refute_empty files
    offenses = files.flat_map do |path|
      bare_references(File.read(File.join(ROOT, path))).map { |reference| "#{path}:#{reference}" }
    end
    assert_empty offenses, "write ::Process or Tokra::Process (plan 039, decision 8)"
  end
end
