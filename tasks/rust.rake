# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "lint"

namespace :rust do
  desc "Check Rust formatting with cargo fmt"
  task :fmt do
    sh "cargo fmt --check"
  end

  namespace :fmt do
    desc "Auto-fix Rust formatting with cargo fmt"
    task :fix do
      sh "cargo fmt"
    end
  end

  desc "Run Clippy with strict settings (configured in Cargo.toml)"
  task :clippy do
    sh "cargo clippy -- -D warnings"
  end

  desc "Fast type checking with cargo check"
  task :check do
    sh "cargo check"
  end

  desc "Forbid #[allow(clippy::...)] except approved exceptions"
  task :no_allows do
    Lint.load(File.expand_path("../clippy_exceptions.rb", __dir__)).enforce!(
      glob: "ext/**/*.rs",
      pattern: /#\[allow\(clippy::/,
      violation_name: "#[allow(clippy::...)]"
    )
  end
end

namespace :lint do
  desc "Run all Rust linting (clippy + fmt check + no unapproved allows)"
  task rust: %w[rust:clippy rust:fmt rust:no_allows]
end
