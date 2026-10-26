# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "lint"

namespace :steep do
  desc "Run Steep type checker"
  task :check do
    sh "bundle exec steep check"
  end

  desc "Forbid 'untyped' in RBS files except approved exceptions"
  task :no_untyped do
    Lint.load(File.expand_path("../rbs_exceptions.rb", __dir__)).enforce!(
      glob: "{sig,plugins/*/sig}/**/*.rbs",
      pattern: /\buntyped\b/,
      reject_pattern: /^\s*#/,
      violation_name: "'untyped' in RBS files"
    )
  end
end

namespace :rbs do
  # Steep checks only sig/ against lib/. Plugin signatures are read here, so
  # a type name they get wrong fails the gate even before plugins get Steep
  # targets of their own.
  desc "Validate every RBS file, plugins included"
  task :validate do
    libraries = %w[logger pathname json uri erb securerandom stringio fileutils date timeout]
    # The clipboard, dialog, notification, and global-shortcut plugins name
    # ferro-arboard's, ferro-rfd's, ferro-notify-rust's, and
    # ferro-global-hotkey's types, from the signatures each gem ships.
    ferro = %w[ferro-arboard ferro-rfd ferro-notify-rust ferro-global-hotkey].map { |name| File.join(Gem::Specification.find_by_name(name).full_gem_path, "sig") }
    dirs = ["sig"] + Dir.glob("plugins/*/sig") + ferro
    sh "bundle", "exec", "rbs", *libraries.flat_map { |name| ["-r", name] }, *dirs.flat_map { |dir| ["-I", dir] }, "validate"
  end

  desc "Check every signature has an implementation and every public method a signature"
  task parity: :compile do
    plugins = Dir.glob("plugins/*").select { |dir| File.directory?(File.join(dir, "lib")) }.sort
    sigs = ["sig"] + plugins.map { |dir| File.join(dir, "sig") }.select { |dir| Dir.exist?(dir) }
    libs = ["lib"] + plugins.map { |dir| File.join(dir, "lib") }
    args = sigs.flat_map { |dir| ["--sig", dir] } + libs.flat_map { |dir| ["--lib", dir] }
    args += %w[--native Tokra::Native --allow rbs_exceptions.rb]
    ruby File.expand_path("rbs_parity.rb", __dir__), *args
  end
end

desc "Run Steep type checker (with no_untyped check)"
task steep: %w[steep:check steep:no_untyped]

namespace :lint do
  desc "Run RBS linting (no unapproved untyped, signature and implementation parity)"
  task rbs: %w[steep:no_untyped rbs:validate rbs:parity]
end
