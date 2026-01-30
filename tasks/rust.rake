# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

class ClippyExceptions
  def self.load(path) = new.tap { |e| e.instance_eval(File.read(path)) }
  def allow(path, line:, reason:) = list << "#{path}:#{line}"
  def to_a = list
  def list = @list ||= []
end

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
    exceptions = ClippyExceptions.load(File.expand_path("../clippy_exceptions.rb", __dir__))

    violations = Dir.glob("ext/**/*.rs")
      .reject { |f| f.include?("/target/") }
      .flat_map { |file| File.readlines(file).map.with_index(1) { |line, n| [file, n, line] } }
      .select { |_, _, line| line.include?("#[allow(clippy::") }
      .reject { |file, n, _| exceptions.to_a.any? { |ex| "#{file}:#{n}".start_with?(ex) } }
      .map { |file, n, line| "  #{file}:#{n}: #{line.strip}" }

    abort <<~ERROR if violations.any?
      ❌ Unapproved #[allow(clippy::...)] found:
      #{violations.join("\n")}

      Add to clippy_exceptions.rb with justification if truly unavoidable.
    ERROR

    puts "✅ No unapproved Clippy allows found"
  end
end

namespace :lint do
  desc "Run all Rust linting (clippy + fmt check + no unapproved allows)"
  task rust: %w[rust:clippy rust:fmt rust:no_allows]
end
