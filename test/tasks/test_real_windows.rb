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

  def test_each_named_plugin_test_checks_the_tripwire_before_it_touches_the_system
    RealWindows::NAMED.each { |path| assert_includes File.read(path), "RealWindowsRun.require!(", path }
  end

  # Every clipboard test writes the system clipboard, so a new file there
  # must be named, or it would run in plugins:test, on the maintainer's.
  def test_every_clipboard_test_runs_with_the_real_window_ones_so_never_on_the_maintainers_clipboard
    files = Dir["plugins/clipboard/test/**/test_*.rb"]

    refute_empty files
    files.each { |path| assert_includes RealWindows::NAMED, path }
    assert_equal %w[test/test_clipboard.rb], RealWindows.plugin_tests("plugins/clipboard", windows: true)
    assert_empty RealWindows.plugin_tests("plugins/clipboard", windows: false)
  end

  HIDDEN_JOB = { "TOKRA_HIDDEN_JOB" => "1" }.freeze

  def test_only_a_set_variable_makes_the_hidden_job
    assert RealWindows.hidden_job?(HIDDEN_JOB)
    refute RealWindows.hidden_job?({})
    refute RealWindows.hidden_job?({ "TOKRA_HIDDEN_JOB" => "" })
    assert_equal "TOKRA_HIDDEN_JOB", RealWindows::HIDDEN_JOB
  end

  def test_the_console_tests_are_real_window_tests_that_exist
    refute_empty RealWindows::CONSOLE
    RealWindows::CONSOLE.each do |path|
      assert_path_exists path
      assert RealWindows.test_file?(path), "#{path} is no real-window test"
    end
  end

  # test:console holds the lock across its child processes; one of them
  # taking it too would wait on its own parent forever. This reads only
  # each console file's own text, not what that file requires.
  def test_no_console_test_takes_the_desktop_input_lock_itself
    RealWindows::CONSOLE.each do |path|
      refute File.fnmatch?(RealWindows::KEYBOARD, path, File::FNM_PATHNAME), path
      refute_match(/taking_the_keyboard|DesktopInputLock/, File.read(path), path)
    end
  end

  def test_the_console_tests_divide_between_core_and_each_plugin
    plugins = Dir["plugins/*"].flat_map { |plugin| RealWindows.console_tests(plugin).map { |path| "#{plugin}/#{path}" } }

    assert_equal RealWindows::CONSOLE.sort, (RealWindows.console_tests + plugins).sort
    assert(RealWindows.console_tests.none? { |path| path.start_with?("plugins/") })
  end

  def test_the_hidden_job_leaves_the_console_tests_out_and_every_other_run_keeps_them
    console = RealWindows::CONSOLE
    paths = ["test/native/test_menu.rb", *console, "test/test_window.rb"]

    assert_equal [["test/native/test_menu.rb", *console], ["test/test_window.rb"]], RealWindows.split(paths, {})
    assert_equal [["test/native/test_menu.rb"], ["test/test_window.rb"]], RealWindows.split(paths, HIDDEN_JOB)
  end

  def test_the_hidden_job_leaves_each_plugins_console_tests_out
    plugins = Dir["plugins/*"].reject { |plugin| RealWindows.console_tests(plugin).empty? }

    refute_empty plugins
    plugins.each do |plugin|
      console = RealWindows.console_tests(plugin)
      everywhere = RealWindows.plugin_tests(plugin, windows: true, env: {})
      hidden = RealWindows.plugin_tests(plugin, windows: true, env: HIDDEN_JOB)

      assert_empty console - everywhere, plugin
      assert_equal everywhere - console, hidden, plugin
      assert_equal RealWindows.plugin_tests(plugin, windows: false, env: {}),
        RealWindows.plugin_tests(plugin, windows: false, env: HIDDEN_JOB), plugin
    end
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
      %w[test:keyboard test:real_windows test:real_windows:plugins test:hidden test:console].each do |name|
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

  def test_hidden_the_gui_task_runs_the_hidden_job_then_the_console_tests_here
    assert_equal ["ran test:hidden", "ran test:console"], gui_runs("hidden")
  end

  # What test:console does where the rest run hidden, with RealWindows::CONSOLE
  # replaced by +console+ if given, before the Rakefile loads. The compile,
  # each plugin's install and tests, and the core batch's command only say
  # what they were given, and whether the desktop input lock was held.
  private def console_runs(console = nil)
    stub = <<~RUBY
      require "rake"
      require_relative "tasks/real_windows"
      if (console = #{console.inspect})
        RealWindows.send(:remove_const, :CONSOLE)
        RealWindows.const_set(:CONSOLE, console.freeze)
      end
      Rake.application.init("rake", [])
      Rake.application.load_rakefile
      held = lambda do
        free = File.open(ENV.fetch("DESKTOP_INPUT_LOCK"), File::RDWR | File::CREAT) do |file|
          file.flock(File::LOCK_EX | File::LOCK_NB)
        end
        free ? "unlocked" : "locked"
      end
      Rake::Task["compile"].clear
      Rake::Task.define_task("compile") { puts "said compile, \#{held.call}" }
      define_singleton_method(:install_plugin_bundle) { |plugin| puts "said bundle \#{plugin}, \#{held.call}" }
      define_singleton_method(:run_plugin_tests) do |plugin, files, windows:, install: true|
        puts "said tests \#{plugin} \#{files.inspect} windows=\#{windows} install=\#{install}, \#{held.call}"
      end
      define_singleton_method(:sh) do |env, command, **|
        puts "said core \#{env.inspect} \#{RealWindows::CONSOLE.select { |path| command.include?(path) }.inspect}, \#{held.call}"
      end
      Rake::Task["test:console"].invoke
    RUBY
    output = nil
    Dir.mktmpdir("console_lock") do |dir|
      env = {
"TOKRA_REAL_WINDOWS" => "hidden",
"DESKTOP_INPUT_LOCK" => File.join(dir, "desktop-input.lock"),
"TOKRA_QUIET" => "1",
"CI" => nil,
}
      output, status = Open3.capture2e(env, RbConfig.ruby, "-e", stub, chdir: File.expand_path("../..", __dir__))

      assert_predicate status, :success?, output
    end
    output.lines(chomp: true).grep(/\Asaid /)
  end

  HELD = RbConfig::CONFIG["host_os"].include?("darwin") ? "locked" : "unlocked"

  # Each plugin's line from test:console: only the dialog plugin's names a
  # file, the console one, and every plugin's may open real windows.
  private def plugin_lines(dialog_files)
    Dir["plugins/*"].map do |plugin|
      files = (plugin == "plugins/dialog") ? dialog_files : []
      "said tests #{plugin} #{files.inspect} windows=true install=false, #{HELD}"
    end
  end

  def test_the_console_tests_run_here_where_the_rest_run_hidden_holding_the_lock_on_a_mac
    assert_equal [
      "said compile, unlocked",
      "said bundle plugins/dialog, unlocked",
      *plugin_lines(%w[test/test_dialog_window.rb]),
], console_runs
  end

  def test_the_core_console_tests_run_in_one_batch_that_may_open_windows_holding_the_lock
    core = "test/integration/event_test.rb"
    run_env = RealWindows.run_env(true)

    assert_equal [
      "said compile, unlocked",
      "said bundle plugins/dialog, unlocked",
      "said core #{run_env.inspect} #{[core].inspect}, #{HELD}",
      *plugin_lines(%w[test/test_dialog_window.rb]),
],
      console_runs([core, "plugins/dialog/test/test_dialog_window.rb"])
  end

  def test_the_gate_fails_rather_than_open_windows_here_when_the_hidden_session_cannot_run_them
    output, status = rake("test:gui")

    refute_predicate status, :success?
    assert_match(/^test:hidden failed: .*TOKRA_REAL_WINDOWS=local/, output)
    refute_includes output, "# Running:"
  end
end
