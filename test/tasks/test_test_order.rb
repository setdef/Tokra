# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "minitest/test_task"
require "tmpdir"
require_relative "../../tasks/test_order"

# Tests the recorded test orders that test:replay runs again.
class TestTestOrder < Minitest::Test
  private def recording(text)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "order.txt")
      File.write(path, text)
      yield path
    end
  end

  private def test_task
    Minitest::TestTask.new(:replayed).tap { |task| task.libs = %w[lib test .] }
  end

  def test_a_recording_keeps_its_seed_and_its_files_in_order_without_comments
    order = recording("# Run 1\nseed 60035\n\ntest/b.rb\ntest/a.rb\n") { |path| TestOrder.read(path) }

    assert_equal TestOrder.new(seed: 60_035, files: %w[test/b.rb test/a.rb]), order
  end

  def test_a_recording_without_a_seed_is_refused
    error = assert_raises(ArgumentError) { recording("test/a.rb\n") { |path| TestOrder.read(path) } }

    assert_match(/records no seed/, error.message)
  end

  def test_the_program_requires_the_files_in_order_after_minitest
    program = TestOrder.new(seed: 13_590, files: %w[test/b.rb test/a.rb]).program(test_task)

    assert_equal %(require "minitest/autorun"; require "test/b.rb"; require "test/a.rb"), program
  end

  def test_the_ruby_arguments_run_the_script_with_the_seed_and_the_extra_arguments
    args = TestOrder.new(seed: 13_590, files: []).ruby_args(test_task, "tmp/replay/x.rb", extra: ["--verbose"])

    assert_equal [
      "-Ilib#{File::PATH_SEPARATOR}test#{File::PATH_SEPARATOR}.",
      "-w",
      "tmp/replay/x.rb",
      "--seed",
      "13590",
      "--verbose",
], args
  end

  # Each recording names test files that exist, so a renamed or deleted
  # test file shows here instead of in a replay that cannot load.
  def test_every_recording_names_existing_files
    Dir["test/fixtures/test_orders/*.txt"].each do |path|
      missing = TestOrder.read(path).files.reject { |file| File.file?(file) }
      assert_empty missing, "#{path} names missing files"
    end
  end
end
