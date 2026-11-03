# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2025 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "English"
require "minitest/test_task"
require "shellwords"
require_relative "test_order"
require_relative "real_windows"
require_relative "hidden_job"

# Clear the default test task created by Minitest::TestTask if it exists
Rake::Task["test"].clear if Rake::Task.task_defined?("test")

desc "Run all tests (the real-window ones first, then Rust, Ruby, and plugins)"
task test: %w[test:gui test:rust test:ruby plugins:test]

# Real-window tests that take the keyboard and mouse on macOS, by opening
# a real menu or bringing a fixture to the front. They run together in one
# process, first, holding the desktop input lock (Plan 046).
KEYBOARD_TESTS = RealWindows::KEYBOARD

# Every test file that opens a real window, the keyboard ones included,
# and the rest. The first run in test:gui, wherever RealWindows.where
# says, and never in test:core (Plan 056).
WINDOW_TESTS, CORE_TESTS = RealWindows.split(Dir["test/**/test_*.rb", "test/**/*_test.rb"])

namespace :test do
  desc "Run Rust tests (requires compile)"
  task rust: :compile do
    CARGO_WORKSPACES.each { |dir| cargo!("test", "--locked", chdir: dir) }
  end

  # Create a specific Minitest task for Ruby core tests
  core = Minitest::TestTask.create(:core) do |t|
    # Test files only: fixture apps under test/integration/fixtures are .rb
    # files that open a real window, and must run only in a child process.
    # The real-window tests run apart, in test:gui.
    t.test_globs = CORE_TESTS
  end

  keyboard = Minitest::TestTask.create(:keyboard) do |t|
    t.test_globs = [KEYBOARD_TESTS]
  end

  real_windows = Minitest::TestTask.create(:real_windows) do |t|
    t.test_globs = WINDOW_TESTS - Dir[KEYBOARD_TESTS]
  end
  # A test process that a native crash ends has no exit status Rake can
  # print ("Command failed with status ()"). On Windows Ruby keeps the
  # exit code shifted left by eight bits, and maps an access violation,
  # an illegal instruction, or a floating-point fault to a signal, which
  # is when the status has none (Ruby win32/win32.c, waitpid). Each Ruby
  # test task prints the whole status when it fails, so its signal, or
  # the low 24 bits of any other NTSTATUS, show (Plan 043).
  #
  # Only the real-window batches may open real windows: the tripwire in
  # test/support/real_windows_run.rb fails any test elsewhere that tries.
  { core: false, keyboard: true, real_windows: true }.each do |name, windows|
    test_task = { core:, keyboard:, real_windows: }.fetch(name)
    Rake::Task["test:#{name}"].clear_actions
    Rake::Task["test:#{name}"].enhance do
      sh RealWindows.run_env(windows), "#{FileUtils::RUBY} #{test_task.make_test_cmd}",
        verbose: test_task.verbose do |ok, status|
        next if ok

        raw = status.to_i
        abort "test:#{name} failed: #{status.inspect}, raw status 0x#{raw.to_s(16)}, code bits 0x#{(raw >> 8).to_s(16)}"
      end
    end
  end

  # Runs the core batch again in each order a crashed run logged
  # (test/fixtures/test_orders, Plan 043), and reports each process's
  # status, so one CI run shows whether an order brings the crash back.
  # With TOKRA_REPLAY_DEBUGGER naming cdb.exe, each order then runs once
  # more under it, which prints the stack of every access violation as it
  # is raised, on whatever thread raises it. A process started under a
  # debugger also gets Windows' debug heap, which fills freed blocks, so a
  # read of freed memory faults there instead of reading stale data.
  desc "Replay the core test orders recorded from crashed runs"
  # The orders hold real-window tests, so they replay only where those run.
  task replay: %w[here compile package:fetch] do
    FileUtils.mkdir_p("tmp/replay")
    extra = Shellwords.split(ENV.fetch("A", ""))
    runs = Dir["test/fixtures/test_orders/*.txt"].map do |path|
      order = TestOrder.read(path)
      script = "tmp/replay/#{File.basename(path, '.txt')}.rb"
      File.write(script, order.program(core))
      [path, order.ruby_args(core, script, extra:)]
    end
    failed = runs.filter_map do |path, args|
      puts "== #{path}"
      ok = system(RealWindows.run_env(true), RbConfig.ruby, *args)
      status = $CHILD_STATUS
      puts "== #{path}: #{ok ? 'passed' : 'failed'}, #{status.inspect}, raw status 0x#{status.to_i.to_s(16)}"
      path unless ok
    end
    if (cdb = ENV.fetch("TOKRA_REPLAY_DEBUGGER", nil))
      File.write("tmp/replay/av.cdb", <<~CDB)
        sxe -c ".lastevent; r; kn 60; gn" -c2 ".lastevent; r; kn 60; q" av
        g
      CDB
      symbols = "srv*#{File.expand_path('tmp/symbols')}*https://msdl.microsoft.com/download/symbols"
      runs.each do |path, args|
        puts "== #{path} under #{cdb}"
        system(RealWindows.run_env(true), cdb, "-G", "-y", symbols, "-cf", "tmp/replay/av.cdb", RbConfig.ruby, *args, in: File::NULL)
        puts "== #{path} under the debugger: #{$CHILD_STATUS.inspect}"
      end
    end
    abort "test:replay failed for #{failed.join(', ')}" unless failed.empty?
  end

  # The packaging check's tests resolve fixture crates with cargo metadata
  # --offline, which needs every platform's dependencies in Cargo's cache;
  # compiling downloads only this machine's.
  task core: "package:fetch"

  desc "Run all Ruby tests (real-window, core, plugins)"
  task ruby: ["test:gui", "test:core", "plugins:test"]

  desc "Run every real-window test: hidden in tokratest on a Mac, here on CI or with TOKRA_REAL_WINDOWS=local"
  task :gui do
    if RealWindows.where == :local
      %w[test:keyboard test:real_windows test:real_windows:plugins].each { |name| Rake::Task[name].invoke }
    else
      Rake::Task["test:hidden"].invoke
    end
  end

  desc "Run every real-window test in tokratest's hidden session, through hidden-run (Plan 056)"
  task :hidden do
    HiddenJob.new(checkout: Dir.pwd).run
  rescue HiddenJob::Failure => e
    abort "test:hidden failed: #{e.message}"
  end

  desc "Remove the hidden session's copies and mirrors of checkouts that are gone (Plan 056)"
  task "hidden:prune" do
    HiddenJob.new(checkout: Dir.pwd).prune
  rescue HiddenJob::Failure => e
    abort "test:hidden:prune failed: #{e.message}"
  end

  # The tasks that open real windows in this session refuse to where the
  # real-window tests belong in the hidden one, and never fall back.
  task :here do
    next if RealWindows.where == :local

    abort "The real-window tests run in tokratest's hidden session on this Mac (rake test:gui or " \
      "test:hidden), so that no window opens in yours. Set TOKRA_REAL_WINDOWS=local to open them here."
  end
  Rake::Task["test:keyboard"].comment = "Run the keyboard-taking real-window tests in this session"
  Rake::Task["test:real_windows"].comment = "Run the other core real-window tests in this session"
  task keyboard: %w[here compile]
  task real_windows: %w[here compile]

  desc "Run the plugins' real-window tests in this session"
  task "real_windows:plugins": :here do
    PLUGINS.each { |plugin| run_plugin_tests(plugin, RealWindows.plugin_tests(plugin, windows: true), windows: true) }
  end
end
