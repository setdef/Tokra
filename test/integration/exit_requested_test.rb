# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/real_app"

# The last window closes in a real app, which then exits or keeps running
# (Plan 038).
#
# Tauri's runtime closes a window whose close request no handler
# prevented, and when the platform reports it destroyed with no window
# left, emits RunEvent::ExitRequested with no code and exits unless a
# handler prevented it (tauri-runtime-wry lib.rs:4168-4185, 4262-4298).
# A prevented app keeps running with no window until AppHandle#exit, whose
# request carries its code (lib.rs:4215-4227).
#
# The window closes through Window#close, which takes the close button's
# path from the native WindowCloseEvent on. The close button itself is the
# one path not driven here:
#
#   bundle exec ruby test/integration/fixtures/exit_requested/app.rb --wait
class ExitRequestedTest < RealApp::TestCase
  # A status no failure path produces.
  EXIT_CODE = 6

  # The events before the app either exits or keeps running.
  CLOSED = [
    "EVENT ready",
    "REPORT",
    "EVENT window Tokra::WindowEvent::CloseRequested",
    "EVENT window Tokra::WindowEvent::Destroyed",
    "EVENT exit-requested nil",
  ].freeze

  def closed
    self.class.fixture_run(:closed) { RealApp.launch("exit_requested") }
  end

  def kept_running
    self.class.fixture_run(:kept_running) do
      RealApp.launch("exit_requested", "--prevent-exit", "--exit-code=#{EXIT_CODE}")
    end
  end

  def test_closing_the_last_window_asks_to_exit_and_the_app_exits_with_zero
    run = closed
    assert_finished run
    assert_equal 0, run.status, run.describe
    assert_equal [*CLOSED, "EVENT exit", "AT_EXIT"], run.kinds, run.describe
  end

  def test_a_prevented_exit_keeps_the_app_running_with_no_window_until_exit
    run = kept_running
    assert_finished run
    assert_equal [
      *CLOSED,
      "PREVENTED",
      "WINDOWS 0",
      "TITLE runtime error: failed to receive message from webview",
      "EVENT exit-requested #{EXIT_CODE}",
      "EVENT exit",
      "AT_EXIT",
    ], run.kinds, run.describe
  end

  def test_the_exit_after_a_prevented_one_ends_the_process_with_its_code
    run = kept_running
    assert_finished run
    assert_equal EXIT_CODE, run.status, run.describe
  end
end
