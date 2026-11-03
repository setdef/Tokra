# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "open3"
require "tmpdir"
require_relative "../../tasks/real_windows"
require "support/real_windows_run"
require "support/native_event_loop"
require "integration/support/real_app"

# Tests which tests open real windows, and where they run (Plan 056).
class TestRealWindows < Minitest::Test
  MAC = "darwin25"

  # The marker's names, spelled so this file does not carry them itself
  # and so count as a real-window test.
  REAL_APP = %w[Real App].join
  EVENT_LOOP = %w[Native Event Loop].join

  def test_on_a_mac_outside_ci_they_run_hidden
    assert_equal :hidden, RealWindows.where({}, MAC)
  end

  def test_on_ci_they_run_here
    assert_equal :local, RealWindows.where({ "CI" => "true" }, MAC)
    assert_equal :local, RealWindows.where({ "CI" => "true" }, "linux-gnu")
    assert_equal :local, RealWindows.where({ "CI" => "true" }, "mingw32")
  end

  def test_only_ci_true_as_github_sets_it_counts_as_ci
    ["", "0", "false", "1", "yes"].each do |value|
      assert_equal :hidden, RealWindows.where({ "CI" => value }, MAC), "CI=#{value.inspect}"
    end
  end

  def test_a_real_window_process_may_open_windows_and_any_other_may_not
    assert_equal({ "TOKRA_REAL_WINDOWS_RUN" => "1" }, RealWindows.run_env(true))
    assert_equal({ "TOKRA_REAL_WINDOWS_RUN" => nil }, RealWindows.run_env(false))
    assert_equal RealWindowsRun::VARIABLE, RealWindows::RUN
  end

  def test_the_tripwire_lets_only_a_real_window_run_through
    assert_nil RealWindowsRun.require!("a window", { "TOKRA_REAL_WINDOWS_RUN" => "1" })
    error = assert_raises(RealWindowsRun::Outside) { RealWindowsRun.require!("a window", {}) }

    assert_match(/\Aa window opens real windows, so it runs only in test:keyboard/, error.message)
  end

  # Runs the block with TOKRA_REAL_WINDOWS_RUN unset, as test:core has it.
  private def outside_a_real_window_run
    saved = ENV.delete(RealWindowsRun::VARIABLE)
    yield
  ensure
    ENV[RealWindowsRun::VARIABLE] = saved if saved
  end

  def test_a_fixture_launched_outside_a_real_window_run_fails_before_any_window_opens
    outside_a_real_window_run do
      error = assert_raises(RealWindowsRun::Outside) { Object.const_get(REAL_APP).launch("event") }

      assert_match(/\A#{REAL_APP}\.launch\("event"\) opens real windows/, error.message)
    end
  end

  def test_the_shared_native_loop_outside_a_real_window_run_fails_before_any_loop_exists
    outside_a_real_window_run do
      loop_holder = Object.const_get(EVENT_LOOP)
      error = assert_raises(RealWindowsRun::Outside) { loop_holder.shared }

      assert_match(/\A#{EVENT_LOOP}\.shared opens real windows/, error.message)
      assert_nil loop_holder.instance_variable_get(:@shared)
    end
  end

  def test_off_macos_they_run_here
    assert_equal :local, RealWindows.where({}, "linux-gnu")
  end

  def test_local_opts_in_to_running_them_here_on_a_mac
    assert_equal :local, RealWindows.where({ "TOKRA_REAL_WINDOWS" => "local" }, MAC)
  end

  def test_hidden_sends_them_away_even_on_ci
    assert_equal :hidden, RealWindows.where({ "TOKRA_REAL_WINDOWS" => "hidden", "CI" => "true" }, "linux-gnu")
  end

  def test_an_empty_choice_is_no_choice
    assert_equal :hidden, RealWindows.where({ "TOKRA_REAL_WINDOWS" => "" }, MAC)
  end

  def test_any_other_choice_is_refused
    error = assert_raises(ArgumentError) { RealWindows.where({ "TOKRA_REAL_WINDOWS" => "yes" }, MAC) }

    assert_equal 'TOKRA_REAL_WINDOWS is local or hidden, not "yes"', error.message
  end

  def test_every_integration_test_opens_real_windows
    assert RealWindows.test_file?("test/integration/keyboard_notice_test.rb", "")
  end

  def test_a_test_that_launches_a_fixture_or_shares_the_native_loop_opens_real_windows
    assert RealWindows.test_file?("plugins/x/test/test_x.rb", "class T < #{REAL_APP}::TestCase")
    assert RealWindows.test_file?("test/native/test_x.rb", "@loop = #{EVENT_LOOP}.shared")
  end

  def test_the_name_alone_in_prose_is_no_marker
    refute RealWindows.test_file?("test/test_x.rb", "# Unlike a #{REAL_APP} fixture, this uses StubNative")
  end

  def test_the_repositorys_own_files_are_sorted
    windows, rest = RealWindows.split(%w[
      test/integration/keyboard/context_menu_test.rb
      test/native/test_window_open.rb
      test/test_window.rb
      test/tasks/test_real_windows.rb
    ])

    assert_equal %w[test/integration/keyboard/context_menu_test.rb test/native/test_window_open.rb], windows
    assert_equal %w[test/test_window.rb test/tasks/test_real_windows.rb], rest
  end

  def test_the_named_plugin_tests_exist_and_open_real_system_ui
    RealWindows::NAMED.each { |path| assert_path_exists path }

    assert_includes RealWindows.plugin_tests("plugins/dialog", windows: true), "test/test_macos_dialogs.rb"
  end

  def test_a_plugins_tests_split_between_the_two_runs
    windows = RealWindows.plugin_tests("plugins/dialog", windows: true)
    rest = RealWindows.plugin_tests("plugins/dialog", windows: false)

    assert_equal %w[test/test_dialog_window.rb test/test_macos_dialogs.rb], windows
    assert_includes rest, "test/test_commands.rb"
    assert_equal Dir["plugins/dialog/test/**/test_*.rb"].map { |path| path.delete_prefix("plugins/dialog/") }.sort,
      (windows + rest).sort
  end

  # The gate's own tasks, in a child rake, with the hidden session's
  # scripts somewhere they are not, so no job can start.
  private def rake(*tasks)
    Dir.mktmpdir("no_hidden_session") do |nowhere|
      env = { "TOKRA_REAL_WINDOWS" => "hidden", "TOKRA_HIDDEN_SESSION" => nowhere }
      Open3.capture2e(env, RbConfig.ruby, "-S", "rake", *tasks, chdir: File.expand_path("../..", __dir__))
    end
  end

  def test_each_task_that_opens_windows_here_refuses_when_they_belong_hidden
    %w[test:keyboard test:real_windows test:real_windows:plugins test:replay].each do |task|
      output, status = rake(task)

      refute_predicate status, :success?, task
      assert_includes output, "Set TOKRA_REAL_WINDOWS=local to open them here.", task
      refute_includes output, "# Running:", task
    end
  end

  # What test:gui invokes where TOKRA_REAL_WINDOWS says +where+, with
  # every task it might invoke replaced by one that only says its name.
  private def gui_runs(where)
    stub = <<~RUBY
      require "rake"
      Rake.application.init("rake", [])
      Rake.application.load_rakefile
      %w[test:keyboard test:real_windows test:real_windows:plugins test:hidden].each do |name|
        Rake::Task[name].clear
        Rake::Task.define_task(name) { puts "ran \#{name}" }
      end
      Rake::Task["test:gui"].invoke
    RUBY
    output, status = Open3.capture2e({ "TOKRA_REAL_WINDOWS" => where }, RbConfig.ruby, "-e", stub,
      chdir: File.expand_path("../..", __dir__))

    assert_predicate status, :success?, output
    output.lines(chomp: true).grep(/\Aran /)
  end

  def test_locally_the_gui_task_runs_the_keyboard_tests_then_the_other_core_ones_then_the_plugins
    assert_equal ["ran test:keyboard", "ran test:real_windows", "ran test:real_windows:plugins"], gui_runs("local")
  end

  def test_hidden_the_gui_task_runs_them_all_through_the_hidden_job
    assert_equal ["ran test:hidden"], gui_runs("hidden")
  end

  def test_the_gate_fails_rather_than_open_windows_here_when_the_hidden_session_cannot_run_them
    output, status = rake("test:gui")

    refute_predicate status, :success?
    assert_match(/^test:hidden failed: .*TOKRA_REAL_WINDOWS=local/, output)
    refute_includes output, "# Running:"
  end
end
