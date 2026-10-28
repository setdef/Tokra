# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2025 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/test_task"

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
  Minitest::TestTask.create(:core) do |t|
    # Test files only: fixture apps under test/integration/fixtures are .rb
    # files that open a real window, and must run only in a child process.
    # The keyboard-taking tests run apart, in test:keyboard.
    t.test_globs = Dir["test/**/test_*.rb", "test/**/*_test.rb"] - Dir[KEYBOARD_TESTS]
  end

  Minitest::TestTask.create(:keyboard) do |t|
    t.test_globs = [KEYBOARD_TESTS]
  end
  # The packaging check's tests resolve fixture crates with cargo metadata
  # --offline, which needs every platform's dependencies in Cargo's cache;
  # compiling downloads only this machine's.
  task core: "package:fetch"

  desc "Run all Ruby tests (keyboard, core, plugins)"
  task ruby: ["test:keyboard", "test:core", "plugins:test"]
end
