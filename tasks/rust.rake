# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "cargo_output"
require_relative "lint"

# Each gem with a native crate is its own Cargo workspace with its own
# Cargo.lock (see Cargo.toml), so every cargo task runs in each of them.
CARGO_WORKSPACES = ["."] + Dir.glob("plugins/*/Cargo.toml").map { |path| File.dirname(path) }.sort

# Runs a cargo command, failing the task on any warning (CargoOutput).
def cargo!(*command, chdir:)
  CargoOutput.run!("cargo", *command, chdir:)
rescue CargoOutput::Failure => e
  abort "❌ #{e.message}"
end

namespace :rust do
  desc "Check Rust formatting with cargo fmt"
  task :fmt do
    CARGO_WORKSPACES.each { |dir| cargo!("fmt", "--all", "--check", chdir: dir) }
  end

  namespace :fmt do
    desc "Auto-fix Rust formatting with cargo fmt"
    task :fix do
      CARGO_WORKSPACES.each { |dir| sh "cargo", "fmt", "--all", chdir: dir }
    end
  end

  desc "Run Clippy with strict settings (configured in each crate's Cargo.toml)"
  task :clippy do
    CARGO_WORKSPACES.each do |dir|
      cargo!("clippy", "--locked", "--all-targets", "--", "-D", "warnings", chdir: dir)
    end
  end

  namespace :clippy do
    desc "Apply Clippy's suggested fixes (rewrites files; review the diff)"
    task :fix do
      CARGO_WORKSPACES.each do |dir|
        sh "cargo", "clippy", "--fix", "--allow-dirty", "--allow-staged", "--locked", "--all-targets", chdir: dir
      end
    end
  end

  desc "Fast type checking with cargo check"
  task :check do
    CARGO_WORKSPACES.each { |dir| cargo!("check", "--locked", "--all-targets", chdir: dir) }
  end

  desc "Forbid #[allow(clippy::...)] except approved exceptions"
  task :no_allows do
    Lint.load(File.expand_path("../clippy_exceptions.rb", __dir__)).enforce!(
      glob: "{ext,plugins/*/ext}/**/*.rs",
      pattern: /#\[allow\(clippy::/,
      violation_name: "#[allow(clippy::...)]"
    )
  end
end

namespace :lint do
  desc "Run all Rust linting (clippy + fmt check + no unapproved allows)"
  task rust: %w[rust:clippy rust:fmt rust:no_allows]
end
