# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "tmpdir"
require_relative "support/keyboard_notice"

# KeyboardNotice decides where Tokra takes the shared desktop input lock
# and maps TOKRA_QUIET onto the gem's speak: keyword. The protocol itself
# is the desktop_input_lock gem's. These tests send the wrapper's calls to
# a real DesktopInputLock on a temporary lock and marker, with a recording
# script in place of osascript, so they never take the shared lock or
# speak.
class KeyboardNoticeTest < Minitest::Test
  QUIET_VARIABLES = %w[CI DESKTOP_INPUT_QUIET TOKRA_QUIET].freeze

  # Stands in for osascript: appends the script it is given to a file
  # beside itself.
  BANNER = <<~SH
    #!/bin/sh
    echo "$2" >> "$(dirname "$0")/banners"
  SH

  # The directory every test's files live under. The gem calls the person
  # back once more as the process exits, so it must outlive the tests: its
  # at_exit is registered after this one, and so runs first.
  def self.root
    @root ||= Dir.mktmpdir("keyboard_notice").tap { |dir| at_exit { FileUtils.remove_entry(dir) } }
  end

  def setup
    @saved = ENV.to_h.slice(*QUIET_VARIABLES)
    QUIET_VARIABLES.each { ENV.delete(it) }
    @dir = Dir.mktmpdir("keyboard_notice", self.class.root)
    @marker = File.join(@dir, "away")
    @banners = File.join(@dir, "banners")
    osascript = File.join(@dir, "osascript")
    File.write(osascript, BANNER)
    File.chmod(0o755, osascript)
    @input = DesktopInputLock.new(lock: File.join(@dir, "lock"), marker: @marker, osascript:,
      say: File.join(@dir, "no-say"), settle: 0.05, env: {}, host_os: "darwin25")
  end

  def teardown
    @input.finish
    QUIET_VARIABLES.each { ENV.delete(it) }
    ENV.update(@saved)
  end

  def test_ci_neither_locks_nor_speaks
    ENV["CI"] = "true"
    refute_predicate KeyboardNotice, :locks?
    refute_predicate KeyboardNotice, :speaks?
    assert_equal :ran, KeyboardNotice.taking_the_keyboard { :ran }
  end

  def test_it_locks_on_a_mac_and_nowhere_else
    assert_equal RbConfig::CONFIG["host_os"].include?("darwin"), KeyboardNotice.locks?
  end

  def test_tokra_quiet_silences_it
    KeyboardNotice.stub(:locks?, true) do
      DesktopInputLock::DEFAULT.stub(:speaks?, true) do
        assert_predicate KeyboardNotice, :speaks?
        ENV["TOKRA_QUIET"] = "1"
        refute_predicate KeyboardNotice, :speaks?
      end
    end
  end

  def test_it_speaks_only_where_the_gem_would
    KeyboardNotice.stub(:locks?, true) do
      DesktopInputLock::DEFAULT.stub(:speaks?, false) { refute_predicate KeyboardNotice, :speaks? }
    end
  end

  def test_it_does_not_speak_where_it_does_not_lock
    KeyboardNotice.stub(:locks?, false) do
      DesktopInputLock::DEFAULT.stub(:speaks?, true) { refute_predicate KeyboardNotice, :speaks? }
    end
  end

  def test_the_real_gem_stays_silent_when_desktop_input_quiet_is_set
    ENV["DESKTOP_INPUT_QUIET"] = "1"
    refute_predicate KeyboardNotice, :speaks?
  end

  def test_without_the_lock_the_block_runs_and_the_gem_is_never_asked
    KeyboardNotice.stub(:locks?, false) do
      DesktopInputLock.stub(:hold, -> (**) { flunk "took the lock" }) do
        assert_equal :ran, KeyboardNotice.taking_the_keyboard { :ran }
      end
    end
  end

  def test_it_holds_the_lock_and_returns_the_blocks_value
    held = nil
    assert_equal :value, taking_the_keyboard { held = lock_held? && :value }
    assert_equal :value, held
    refute lock_held?
  end

  def test_it_speaks_to_the_person_by_default
    assert taking_the_keyboard { File.exist?(@marker) }, "no marker while the span ran"
    assert_includes File.read(@banners), "step away"
  end

  def test_tokra_quiet_maps_to_a_silent_span
    ENV["TOKRA_QUIET"] = "1"
    held = nil
    taking_the_keyboard { held = lock_held? }
    assert held, "the lock was not held"
    refute_path_exists @marker
    refute_path_exists @banners
  end

  def test_speak_false_maps_to_a_silent_span
    taking_the_keyboard(speak: false) { :ran }
    refute_path_exists @marker
    refute_path_exists @banners
  end

  # Runs KeyboardNotice.taking_the_keyboard as on a Mac, with the gem's
  # shared instance replaced by the test's own.
  private def taking_the_keyboard(**, &)
    KeyboardNotice.stub(:locks?, true) do
      DesktopInputLock.stub(:hold, -> (speak: true, &block) { @input.hold(speak:, &block) }) do
        KeyboardNotice.taking_the_keyboard(**, &)
      end
    end
  end

  private def lock_held?
    File.open(File.join(@dir, "lock")) { |file| !file.flock(File::LOCK_EX | File::LOCK_NB) }
  end
end
