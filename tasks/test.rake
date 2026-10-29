# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2025 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "English"
require "minitest/test_task"
require "shellwords"
require_relative "test_order"

# Clear the default test task created by Minitest::TestTask if it exists
Rake::Task["test"].clear if Rake::Task.task_defined?("test")

desc "Run all tests (the keyboard-taking ones first, then Rust, Ruby, and plugins)"
task test: %w[test:keyboard test:rust test:ruby plugins:test]

# Real-window tests that take the keyboard and mouse on macOS, by opening
# a real menu or bringing a fixture to the front. They run together in one
# process, first, so KeyboardNotice asks the person at the Mac to step away
# once, for a short stretch, and calls them back before the rest runs.
KEYBOARD_TESTS = "test/integration/keyboard/**/*_test.rb"

namespace :test do
  desc "Run Rust tests (requires compile)"
  task rust: :compile do
    CARGO_WORKSPACES.each { |dir| cargo!("test", "--locked", chdir: dir) }
  end

  # Create a specific Minitest task for Ruby core tests
  core = Minitest::TestTask.create(:core) do |t|
    # Test files only: fixture apps under test/integration/fixtures are .rb
    # files that open a real window, and must run only in a child process.
    # The keyboard-taking tests run apart, in test:keyboard.
    t.test_globs = Dir["test/**/test_*.rb", "test/**/*_test.rb"] - Dir[KEYBOARD_TESTS]
  end

  keyboard = Minitest::TestTask.create(:keyboard) do |t|
    t.test_globs = [KEYBOARD_TESTS]
  end
  # A test process that a native crash ends has no exit status Rake can
  # print ("Command failed with status ()"). On Windows Ruby keeps the
  # exit code shifted left by eight bits, and maps an access violation,
  # an illegal instruction, or a floating-point fault to a signal, which
  # is when the status has none (Ruby win32/win32.c, waitpid). Each Ruby
  # test task prints the whole status when it fails, so its signal, or
  # the low 24 bits of any other NTSTATUS, show (Plan 043).
  { core:, keyboard: }.each do |name, test_task|
    Rake::Task["test:#{name}"].clear_actions
    Rake::Task["test:#{name}"].enhance do
      ruby test_task.make_test_cmd, verbose: test_task.verbose do |ok, status|
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
  task replay: %w[compile package:fetch] do
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
      ok = system(RbConfig.ruby, *args)
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
        system(cdb, "-G", "-y", symbols, "-cf", "tmp/replay/av.cdb", RbConfig.ruby, *args, in: File::NULL)
        puts "== #{path} under the debugger: #{$CHILD_STATUS.inspect}"
      end
    end
    abort "test:replay failed for #{failed.join(', ')}" unless failed.empty?
  end

  # The packaging check's tests resolve fixture crates with cargo metadata
  # --offline, which needs every platform's dependencies in Cargo's cache;
  # compiling downloads only this machine's.
  task core: "package:fetch"

  desc "Run all Ruby tests (keyboard, core, plugins)"
  task ruby: ["test:keyboard", "test:core", "plugins:test"]
end
