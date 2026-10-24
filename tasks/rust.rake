# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "lint"

# Each gem with a native crate is its own Cargo workspace with its own
# Cargo.lock (see Cargo.toml), so every cargo task runs in each of them.
CARGO_WORKSPACES = ["."] + Dir.glob("plugins/*/Cargo.toml").map { |path| File.dirname(path) }.sort

namespace :rust do
  desc "Check Rust formatting with cargo fmt"
  task :fmt do
    CARGO_WORKSPACES.each { |dir| sh "cargo fmt --check", chdir: dir }
  end

  namespace :fmt do
    desc "Auto-fix Rust formatting with cargo fmt"
    task :fix do
      CARGO_WORKSPACES.each { |dir| sh "cargo fmt", chdir: dir }
    end
  end

  desc "Run Clippy with strict settings (configured in Cargo.toml)"
  task :clippy do
    CARGO_WORKSPACES.each { |dir| sh "cargo clippy -- -D warnings", chdir: dir }
  end

  desc "Fast type checking with cargo check"
  task :check do
    CARGO_WORKSPACES.each { |dir| sh "cargo check", chdir: dir }
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
