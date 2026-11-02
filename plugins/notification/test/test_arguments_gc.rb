# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/notification_test"

# The date reader raises one of ferro-time's errors for every date time
# refuses. ferro-time 0.1.0.pre.1 and pre.2 kept an error's arguments in a
# Rust Vec while Ruby allocated the exception, so a collection in that
# window freed them and crashed Ruby (ferro-time 0.1.0.pre.3 CHANGELOG,
# Fixed; Plan 048).
class TestArgumentsGc < Minitest::Test
  include NotificationTest

  # A date for each error shape the reader reaches: a component out of
  # range, trailing input, and a string that is no date.
  REFUSED_DATES = [
    "2026-02-30T00:00:00Z",
    "2026-10-26T12:00:00Zjunk",
    "not a date",
  ].freeze

  # What time says of each, in order.
  EXPECTED = [
    "day was not in range",
    "unexpected trailing characters; the end of input was expected",
    "the 'year' component could not be parsed",
  ].freeze

  # Runs in a child Ruby, so a crash fails this test and not the suite.
  # Under GC.stress every allocation collects, so each error is built
  # while a collection runs between the allocation of the exception and
  # the reading of its arguments.
  def test_refused_dates_raise_under_gc_stress
    script = <<~RUBY
      require "tokra-notification"
      arguments = Tokra::Plugins::Notification::Commands::Arguments
      messages = []
      GC.stress = true
      #{REFUSED_DATES.inspect}.each do |date|
        options = { "schedule" => { "at" => { "date" => date } } }
        begin
          arguments.new({ "options" => options }, "notify").notification_data
        rescue Tokra::Error::InvalidArgs => e
          messages << e.message
        end
      end
      GC.stress = false
      puts messages
    RUBY
    output, errors, status = run_child(script)

    assert_predicate status, :success?, "the child Ruby crashed or failed: #{errors.lines.first(3).join}"
    prefix = "invalid args `options` for command `notify`: "
    assert_equal EXPECTED.map { |message| prefix + message }, output.lines.map(&:chomp)
  end

  # The child's output, errors, and status. A child that outlives
  # CHILD_LIMIT is killed and the test fails, as in_child does.
  private def run_child(script)
    Open3.popen3(RbConfig.ruby, "-I", LIB, "-e", script) do |stdin, stdout, stderr, thread|
      stdin.close
      output = Thread.new { stdout.read }
      errors = Thread.new { stderr.read }
      unless thread.join(CHILD_LIMIT)
        Process.kill(:KILL, thread.pid)
        flunk "the child Ruby ran past #{CHILD_LIMIT} s and was killed"
      end
      [output.value, errors.value, thread.value]
    end
  end
end
