# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2025 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/test_task"

# Clear the default test task created by Minitest::TestTask if it exists
Rake::Task["test"].clear if Rake::Task.task_defined?("test")

desc "Run all tests (Rust first, then Ruby, then plugins)"
task test: %w[test:rust test:ruby plugins:test]

namespace :test do
  desc "Run Rust tests (requires compile)"
  task rust: :compile do
    sh "cargo test"
  end

  # Create a specific Minitest task for Ruby tests
  Minitest::TestTask.create(:ruby) do |t|
    t.test_globs = ["test/**/*.rb"]
  end
end
