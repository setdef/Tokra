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
  # window, prints READY and the top-level window's handle, and then
  # either sleeps, so its thread takes no message, as a main thread
  # blocked in a call takes none, or, given "pump", pumps messages with
  # GetMessageW, as an idle event loop does.
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
    $stdout.puts "READY \#{top}"
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

  # A second child, given the handle of a window of CHILD's: given
  # "send", it prints READY and sends that window a WM_NULL with
  # SendMessageW, which waits until the window's thread takes it, as
  # DestroyWindow waits on a window of another thread; given "adopt", it
  # makes a window of its own inside that one, as WebView2's browser
  # does inside a webview's, prints READY, and sleeps until with_child
  # kills it.
  HELPER = <<~RUBY
    require "fiddle"
    user32 = Fiddle.dlopen("user32")
    mode, window = ARGV.first, Integer(ARGV.fetch(1))
    if mode == "send"
      $stdout.puts "READY"
      $stdout.flush
      send = Fiddle::Function.new(user32["SendMessageW"],
        [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_UINT, Fiddle::TYPE_UINTPTR_T, Fiddle::TYPE_INTPTR_T], Fiddle::TYPE_INTPTR_T)
      send.call(window, 0, 0, 0)
    else
      wide = ->(text) { (text + "\\0").encode(Encoding::UTF_16LE) }
      create = Fiddle::Function.new(user32["CreateWindowExW"], [Fiddle::TYPE_UINT, Fiddle::TYPE_VOIDP,
        Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT, Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_INT,
        Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INTPTR_T)
      # WS_EX_NOPARENTNOTIFY, so the parent's thread is sent nothing, and
      # WS_CHILD, hidden.
      adopted = create.call(0x4, wide.("STATIC"), wide.("hang-probe-adopted"), 0x40000000, 0, 0, 10, 10, window, 0, 0, nil)
      abort "CreateWindowExW failed" if adopted.zero?
      $stdout.puts "READY \#{adopted}"
      $stdout.flush
      sleep
    end
  RUBY

  # Seconds the child gets to make its windows.
  READY = 30
  # Seconds the probe gets to see the helper blocked in SendMessageW.
  BLOCKED = 30

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
      assert_match(/^wait chains:\nthread \d+ nodes=\d+ cycle=(?:true|false)/, probe)
      assert_match(/^threads:\nthread \d+ /, probe)
      assert_match(/^stacks:/, probe)
      assert_match(/^owner stacks: no other process owns a window in the tree$/, probe)
    end
  end

  # A thread blocked in SendMessageW to a window of a thread that takes
  # no message: WCT names the blocked thread first, then the SendMessage,
  # then the thread it waits on, in the other process. Every field the
  # probe reads is known here, at the first three offsets of the node
  # array, so a wrong WAITCHAIN_NODE_INFO size or offset fails this.
  #
  # WaitTime and ContextSwitches, though, are matched only as numbers,
  # so reading them swapped would pass. WAITCHAIN_NODE_INFO's
  # reference gives WaitTime only as "The wait time", with no unit or
  # starting point, so no property of it that tells it from a count of
  # context switches, such as growing while the thread waits, has a
  # source to check it against; their order rests on wct.h and
  # windows-sys alone.
  def test_on_windows_the_probe_follows_a_send_message_to_the_thread_it_waits_on
    skip "the probe looks only on Windows" unless RealApp.windows?

    with_child("sleep") do |pid, window|
      receiver = HangProbe::Win32.owner(window).first
      with_child("send", window, script: HELPER) do |sender|
        expected = /^  Thread status=Blocked pid=#{sender} thread=\d+ wait_time=\d+ context_switches=\d+\n  SendMessage status=\w+ name="[^"\n]*"\n  Thread status=\w+ pid=#{pid} thread=#{receiver} /
        chains = until_matched(expected) { HangProbe::Win32.wait_chains(sender) }

        assert_match(expected, chains)
        assert_match(/\Await chains:\n/, chains)
      end
    end
  end

  # A window another process made inside the fixture's: the probe lists
  # it under the fixture's window and reads that process's stacks too,
  # starting with the thread that owns it.
  def test_on_windows_the_probe_reads_the_stacks_of_each_other_process_with_a_window_in_the_tree
    skip "the probe looks only on Windows" unless RealApp.windows?

    with_child("pump") do |pid, window|
      with_child("adopt", window, script: HELPER) do |helper, adopted|
        owner = HangProbe::Win32.owner(adopted).first
        probe = HangProbe.call(pid)

        assert_match(/^  0x#{adopted.to_s(16)} class="Static" title="hang-probe-adopted" thread=#{owner} pid=#{helper} /,
          probe)
        assert_match(/^owner stacks:\nstacks of pid #{helper} \(window threads #{owner}\):\n/, probe)
        next unless File.exist?(HangProbe::Win32::CDB)

        # ~*kn heads each thread's stack with its "Id: pid.tid" line,
        # which "~ (Thread Status)" shows as "id: 4dc.470", and ~~[tid]kn
        # does not, so a stack before the first such line is the owner
        # thread's, printed first.
        assert_match(/^stacks of pid #{helper} \(window threads #{owner}\):\n(?:(?![Ii]d: \h+\.\h+ ).)*Child-SP/m,
          probe)
      end
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

  # Runs +script+ with +mode+ and +args+, yields its pid and any window
  # handle its READY line names once it is ready, and kills and reaps it
  # after.
  private def with_child(mode, *args, script: CHILD)
    reader, writer = IO.pipe
    begin
      pid = Process.spawn(RbConfig.ruby, "-e", script, mode, *args.map(&:to_s), out: writer)
    ensure
      writer.close
    end
    line = Thread.new { reader.gets }.join(READY)&.value
    assert_match(/\AREADY(?: \d+)?\n\z/, line.to_s, "the child (#{mode}) was not ready within #{READY} s")
    yield pid, line.split[1]&.to_i
  ensure
    if pid
      RealApp.signal(pid, :KILL)
      Process.wait(pid)
    end
    reader&.close
  end

  # What the block answers once it matches +pattern+, or when BLOCKED
  # seconds pass, its last answer.
  private def until_matched(pattern)
    deadline = RealApp.now + BLOCKED
    loop do
      answer = yield
      return answer if answer.match?(pattern) || RealApp.now > deadline

      sleep 0.5
    end
  end

  private def run_with(probe:)
    RealApp::Run.new(status: nil, termsig: nil, stdout: "PROGRESS ready 0.000\n", stderr: "warned\n", timed_out: true,
      seconds: 60.0, exit_after_signal: nil, activated: nil, probe:)
  end
end
