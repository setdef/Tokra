# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# The order one logged test run ran its tests in, so another run can
# repeat it.
#
# A test batch's order comes from two places. Minitest::TestTask requires
# the test files in a shuffled order no seed controls (minitest 6.0.1
# <tt>lib/minitest/test_task.rb</tt>, +make_test_cmd+), which sets the order
# Minitest learns its test classes in; the run's seed then shuffles those
# classes, and each class's methods (<tt>lib/minitest.rb</tt>, +run_all_suites+;
# <tt>lib/minitest/test.rb</tt>, +runnable_methods+). The seed alone repeats a
# run only with the same file order, so a recorded order keeps both: the
# files in the order the logged command required them, and the seed the
# run printed.
#
# A recording is a text file: a line <tt>seed N</tt>, one test file per
# line in require order, and comment lines starting with <tt>#</tt>.
class TestOrder < Data.define(:seed, :files)
  # Reads the recording at +path+.
  def self.read(path)
    seed = nil
    files = []
    File.readlines(path, chomp: true).each do |line|
      line = line.strip
      next if line.empty? || line.start_with?("#")

      if (match = line.match(/\Aseed (\d+)\z/))
        seed = Integer(match[1])
      else
        files << line
      end
    end
    raise ArgumentError, "#{path} records no seed" unless seed

    new(seed:, files:)
  end

  # The Ruby program that runs these files in this order, as +test_task+
  # (a Minitest::TestTask) writes it after <tt>ruby -e</tt>.
  def program(test_task)
    [test_task.framework, *files.map { |file| %(require "#{file}") }].join("; ")
  end

  # The arguments to Ruby that run +script+, a file holding #program, with
  # +test_task+'s options and this seed, followed by +extra+ arguments for
  # Minitest. A file in place of <tt>-e</tt> keeps the command line free of
  # quotes, which a debugger in front of Ruby may not pass on as given.
  def ruby_args(test_task, script, extra: [])
    args = ["-I#{test_task.libs.join(File::PATH_SEPARATOR)}"]
    args << "-w" if test_task.warning
    args + [script, "--seed", seed.to_s, *extra]
  end
end
