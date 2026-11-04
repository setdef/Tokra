# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/real_app"

# RealApp's output collection, which shows what a hung fixture printed
# before it was killed (plan 051), and the HangProbe report that
# describe adds below that output for a fixture that hung.
class RealAppTest < Minitest::Test
  # A child that makes a hidden top-level window holding one child
  # window, prints READY, and then either sleeps, so its thread takes no
  # message, as a main thread blocked in a call takes none, or, given
  # "pump", pumps messages with GetMessageW, as an idle event loop does.
  CHILD = <<~RUBY
    require "fiddle"
    user32 = Fiddle.dlopen("user32")
    wide = ->(text) { (text + "\\0").encode(Encoding::UTF_16LE) }
    create = Fiddle::Function.new(user32["CreateWindowExW"], [Fiddle::TYPE_UINT, Fiddle::TYPE_VOIDP,
      Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT, Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_INT,
      Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INTPTR_T)
    top = create.call(0, wide.("STATIC"), wide.("hang-probe"), 0, 0, 0, 100, 100, 0, 0, 0, nil)
    # WS_CHILD | WS_VISIBLE
    create.call(0, wide.("STATIC"), wide.("hang-probe-child"), 0x50000000, 0, 0, 50, 50, top, 0, 0, nil)
    $stdout.puts "READY"
    $stdout.flush
    if ARGV.first == "pump"
      get = Fiddle::Function.new(user32["GetMessageW"],
        [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_UINT, Fiddle::TYPE_UINT], Fiddle::TYPE_INT)
      dispatch = Fiddle::Function.new(user32["DispatchMessageW"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INTPTR_T)
      message = Fiddle::Pointer.malloc(64, Fiddle::RUBY_FREE)
      dispatch.call(message) while get.call(message, 0, 0, 0).positive?
    else
      sleep 120
    end
  RUBY

  # Seconds the child gets to make its windows.
  READY = 30

  def test_describe_ends_with_the_probe_of_an_app_that_hung
    run = run_with(probe: "windows: none")

    assert run.describe.end_with?("--- stderr\nwarned\n\n--- probe\nwindows: none"), run.describe
  end

  def test_describe_has_no_probe_section_when_nothing_was_probed
    run = run_with(probe: nil)

    assert run.describe.end_with?("--- stderr\nwarned\n"), run.describe
    refute_includes run.describe, "--- probe"
  end

  def test_off_windows_the_probe_finds_nothing
    skip "the probe looks only on Windows" if RealApp.windows?

    assert_nil HangProbe.call(Process.pid)
  end

  # The probe names the hung child's window and, indented under it, the
  # window inside it, says their thread took no message, and lists the
  # child's threads.
  def test_on_windows_the_probe_names_each_window_whose_thread_takes_no_message
    skip "the probe looks only on Windows" unless RealApp.windows?

    with_child("sleep") do |pid|
      probe = HangProbe.call(pid)

      assert_match(/^0x\h+ class="Static" title="hang-probe" thread=\d+ pid=#{pid} visible=false hung=\w+ answers_wm_null=false$/,
        probe)
      assert_match(/^  0x\h+ class="Static" title="hang-probe-child" thread=\d+ pid=#{pid} visible=false hung=\w+ answers_wm_null=false$/,
        probe)
      assert_match(/^threads:\nthread \d+ /, probe)
      assert_match(/^stacks:/, probe)
    end
  end

  # A thread that pumps messages takes the probe's WM_NULL.
  def test_on_windows_the_probe_says_a_pumping_thread_takes_its_message
    skip "the probe looks only on Windows" unless RealApp.windows?

    with_child("pump") do |pid|
      probe = HangProbe.call(pid)

      assert_match(/^0x\h+ class="Static" title="hang-probe" thread=\d+ pid=#{pid} visible=false hung=false answers_wm_null=true$/,
        probe)
      assert_match(/^  0x\h+ class="Static" title="hang-probe-child" .* answers_wm_null=true$/, probe)
    end
  end

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

  # Runs CHILD with +mode+, yields its pid once its windows exist, and
  # kills and reaps it after.
  private def with_child(mode)
    reader, writer = IO.pipe
    begin
      pid = Process.spawn(RbConfig.ruby, "-e", CHILD, mode, out: writer)
    ensure
      writer.close
    end
    line = Thread.new { reader.gets }.join(READY)&.value
    assert_equal "READY\n", line, "the child never made its windows within #{READY} s"
    yield pid
  ensure
    if pid
      RealApp.signal(pid, :KILL)
      Process.wait(pid)
    end
    reader&.close
  end

  private def run_with(probe:)
    RealApp::Run.new(status: nil, termsig: nil, stdout: "PROGRESS ready 0.000\n", stderr: "warned\n", timed_out: true,
      seconds: 60.0, exit_after_signal: nil, activated: nil, probe:)
  end
end
