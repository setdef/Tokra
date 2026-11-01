# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "open3"
require "stringio"
require "tmpdir"
require_relative "support/keyboard_notice"

# KeyboardNotice takes a lock and speaks only where a person may be
# typing, and never in these tests: each Desk here locks and marks files
# in a temporary directory, never the shared ones in /tmp, and speaks into
# a recorder.
class KeyboardNoticeTest < Minitest::Test
  QUIET_VARIABLES = %w[CI DESKTOP_INPUT_QUIET TOKRA_QUIET].freeze

  # A Ruby that takes the lock, says so, waits for a line on its standard
  # input, says it is releasing, and only then releases.
  HOLDER = <<~RUBY
    $stdout.sync = true
    lock = File.open(ARGV[0], File::RDONLY | File::CREAT, 0o666)
    lock.flock(File::LOCK_EX)
    puts "locked"
    $stdin.gets
    puts "releasing"
    lock.flock(File::LOCK_UN)
  RUBY

  def setup
    @saved = ENV.to_h.slice(*QUIET_VARIABLES)
    QUIET_VARIABLES.each { ENV.delete(it) }
    @dir = Dir.mktmpdir("keyboard_notice")
    @lock_path = File.join(@dir, "desktop-input.lock")
    @marker_path = File.join(@dir, "desktop-input.away")
    @said = []
    @spoken = Thread::Queue.new
    @desks = []
    @now = 0.0
  end

  def teardown
    @desks.each(&:stop)
    FileUtils.remove_entry(@dir)
    QUIET_VARIABLES.each { ENV.delete(it) }
    ENV.update(@saved)
  end

  def test_ci_neither_locks_nor_speaks
    ENV["CI"] = "true"
    refute_predicate KeyboardNotice, :locks?
    refute_predicate KeyboardNotice, :speaks?
    assert_equal :ran, KeyboardNotice.taking_the_keyboard { :ran }
  end

  def test_it_locks_on_a_mac
    assert_equal RbConfig::CONFIG["host_os"].include?("darwin"), KeyboardNotice.locks?
  end

  def test_tokra_quiet_silences_it
    ENV["TOKRA_QUIET"] = "1"
    refute_predicate KeyboardNotice, :speaks?
  end

  def test_desktop_input_quiet_silences_it
    ENV["DESKTOP_INPUT_QUIET"] = "1"
    refute_predicate KeyboardNotice, :speaks?
  end

  def test_it_speaks_on_a_mac_with_say_and_no_quieting_variable
    expected = RbConfig::CONFIG["host_os"].include?("darwin") && File.executable?("/usr/bin/say")
    assert_equal expected, KeyboardNotice.speaks?
  end

  # Quiet still locks, so that two projects' tests never collide.
  def test_quiet_still_takes_the_lock_but_never_speaks
    desk = new_desk
    KeyboardNotice.stub(:locks?, true) do
      KeyboardNotice.stub(:speaks?, false) do
        KeyboardNotice.stub(:desk, desk) do
          KeyboardNotice.taking_the_keyboard { refute lock_free?, "the lock was not held" }
        end
      end
    end
    assert_empty @said
    refute_path_exists @marker_path
  end

  def test_the_first_span_marks_and_warns_and_the_call_back_unmarks
    desk = new_desk
    assert_equal :ran, desk.taking_the_keyboard { :ran }
    assert_equal [KeyboardNotice::STEP_AWAY], @said
    assert_equal ::Process.pid, marker_pid

    desk.call_back
    assert_equal [KeyboardNotice::STEP_AWAY, KeyboardNotice::COME_BACK], @said
    refute_path_exists @marker_path
  end

  def test_a_marker_from_an_ended_process_is_replaced_and_warned
    File.write(@marker_path, "#{ended_pid} 0")
    new_desk.taking_the_keyboard
    assert_equal [KeyboardNotice::STEP_AWAY], @said
    assert_equal ::Process.pid, marker_pid
  end

  def test_a_marker_from_a_live_process_means_someone_already_warned
    File.write(@marker_path, "#{::Process.pid} 0")
    new_desk.taking_the_keyboard
    assert_empty @said
    assert_equal ::Process.pid, marker_pid
  end

  def test_a_marker_from_a_process_we_may_not_signal_still_means_someone_already_warned
    skip "Windows has no pid 1 to refuse the signal with EPERM" if Gem.win_platform?
    File.write(@marker_path, "1 0")
    new_desk.taking_the_keyboard
    assert_empty @said
    assert_equal 1, marker_pid
  end

  def test_the_call_back_waits_while_someone_else_holds_the_lock
    File.write(@marker_path, "1 0")
    desk = new_desk
    File.open(@lock_path, File::RDONLY | File::CREAT) do |other|
      other.flock(File::LOCK_EX)
      desk.call_back
      assert_empty @said
      assert_path_exists @marker_path
    end
    desk.call_back
    assert_equal [KeyboardNotice::COME_BACK], @said
    refute_path_exists @marker_path
  end

  def test_silent_spans_neither_speak_nor_touch_the_marker
    desk = new_desk
    desk.taking_the_keyboard(speak: false) { refute lock_free?, "the lock was not held" }
    refute_path_exists @marker_path

    File.write(@marker_path, "#{ended_pid} 0")
    desk.taking_the_keyboard(speak: false)
    @now += KeyboardNotice::SETTLE + 1
    desk.tick
    assert_empty @said
    assert_path_exists @marker_path, "a silent span armed the watcher's call back"
  end

  # Two spans in a row are one stretch: one warning before the first, and
  # one call back only once SETTLE seconds pass with neither running. The
  # clock is fake and the test polls the watcher's tick itself.
  def test_a_stretch_is_announced_once_and_called_back_once_it_settles
    desk = new_desk
    desk.taking_the_keyboard
    @now += 0.6
    desk.tick
    desk.taking_the_keyboard { assert_equal [KeyboardNotice::STEP_AWAY], @said }
    @now += KeyboardNotice::SETTLE - 0.01
    desk.tick
    assert_equal [KeyboardNotice::STEP_AWAY], @said, "called back before the stretch settled"

    @now += 0.02
    desk.tick
    desk.tick
    assert_equal [KeyboardNotice::STEP_AWAY, KeyboardNotice::COME_BACK], @said
    refute_path_exists @marker_path
  end

  # The real watcher is a thread that polls tick on the real clock. The
  # timeout only stops a broken watcher from hanging the run.
  def test_the_watcher_thread_calls_back_on_its_own
    desk = new_desk(settle: 0.1, clock: KeyboardNotice::Desk::CLOCK, watcher: true)
    desk.taking_the_keyboard
    @spoken.clear
    refute_nil @spoken.pop(timeout: 30), "the watcher never called back"
    assert_equal [KeyboardNotice::STEP_AWAY, KeyboardNotice::COME_BACK], @said
  end

  # A nested span that returns at all shares the outer one's lock; the
  # join's timeout only stops a deadlock from hanging the run.
  def test_nested_spans_share_one_lock
    desk = new_desk
    inner = Thread.new do
      desk.taking_the_keyboard { desk.taking_the_keyboard(speak: false) { :inner } }
    end
    assert_equal :inner, inner.join(30)&.value, "a nested span deadlocked on the lock"
    assert lock_free?, "the lock outlived the outer span"
  end

  def test_the_lock_is_released_when_the_block_raises
    desk = new_desk
    assert_raises(ZeroDivisionError) { desk.taking_the_keyboard { 1 / 0 } }
    assert lock_free?
  end

  # The child writes "releasing" before it releases, so a span that starts
  # only once the lock is free always finds that line already written.
  def test_a_span_waits_for_another_process_to_release_the_lock
    log_reader, log_writer = IO.pipe
    desk = new_desk(err: log_writer)
    Open3.popen2(RbConfig.ruby, "-e", HOLDER, @lock_path) do |child_in, child_out, child|
      assert_equal "locked", child_out.gets&.chomp
      span = Thread.new do
        desk.taking_the_keyboard(speak: false) { child_out.read_nonblock(100, exception: false) }
      end
      assert log_reader.wait_readable(10), "the span did not wait for the lock"
      assert_equal "#{KeyboardNotice::WAITING}\n", log_reader.gets

      child_in.puts "go"
      assert_equal "releasing", span.value.chomp
      assert_predicate child.value, :success?
    end
  end

  private def new_desk(settle: KeyboardNotice::SETTLE, err: StringIO.new, clock: -> { @now }, watcher: false)
    desk = KeyboardNotice::Desk.new(lock_path: @lock_path, marker_path: @marker_path, settle:, err:, clock:, watcher:,
      voice: -> (words) { @spoken << (@said << words) })
    @desks << desk
    desk
  end

  private def lock_free?
    (File.open(@lock_path, File::RDONLY | File::CREAT) { it.flock(File::LOCK_EX | File::LOCK_NB) }) ? true : false
  end

  private def marker_pid
    Integer(File.read(@marker_path).split.first)
  end

  # The pid of a process that has ended and been reaped.
  private def ended_pid
    pid = ::Process.spawn(RbConfig.ruby, "-e", "")
    ::Process.wait(pid)
    pid
  end
end
