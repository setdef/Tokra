# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/real_app"

# RealApp's output collection, which shows what a hung fixture printed
# before it was killed (plan 051).
class RealAppTest < Minitest::Test
  # Through launch's own readers: the child exits, but its grandchild
  # holds stdout open, so its reader never sees the stream end and drain
  # gives up once its limit, a backstop, passes.
  def test_launch_keeps_what_arrived_on_streams_still_open_after_the_child_ends
    run = RealApp.launch("open_stream", drain: 0.2)
    grandchild = run.lines.grep(/\AGRANDCHILD /).first&.split&.last&.to_i
    note = "(stream still open after 0.2 s)"

    assert_equal "PROGRESS ready 0.000\nGRANDCHILD #{grandchild}\n#{note}", run.stdout, run.describe
    assert_equal "stderr before the end\n", run.stderr, run.describe
  ensure
    RealApp.signal(grandchild, :KILL) if grandchild&.positive?
  end

  def test_drain_keeps_what_a_stream_still_open_already_sent
    reader, writer = IO.pipe
    buffer = +""
    read = Thread::Queue.new
    thread = Thread.new do
      reader.each_line do |line|
        buffer << line
        read << line
      end
    end
    writer.write("PROGRESS ready 0.120\n")
    refute_nil read.pop(timeout: 5), "the reader never read the line"

    assert_equal "PROGRESS ready 0.120\n(stream still open after 0.01 s)", RealApp.drain(thread, buffer, 0.01)
  ensure
    writer&.close
    thread&.join(5)
    reader&.close
  end

  def test_drain_answers_the_whole_stream_once_it_ends
    reader, writer = IO.pipe
    buffer = +""
    thread = Thread.new { reader.each_line { |line| buffer << line } }
    writer.write("PROGRESS ready 0.120\nREPORT {}\n")
    writer.close

    assert_equal "PROGRESS ready 0.120\nREPORT {}\n", RealApp.drain(thread, buffer)
  ensure
    reader&.close
  end
end
