# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2025 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "bundler/gem_tasks"

require "rdoc/task"
RDoc::Task.new do |rdoc|
  rdoc.rdoc_dir = ENV["RDOC_OUTPUT"] || "tmp/rdoc"
  rdoc.rdoc_files.include("lib/**/*.rb", "ext/**/*.rb", "examples/**/*.rb", "README.rdoc")
  rdoc.rdoc_files.exclude("**/*.rbs", "examples/verify_*/**/*")
  # Include plugin lib files in RDoc
  rdoc.rdoc_files.include("plugins/*/lib/**/*.rb")
end

# Rust extension compilation
require "rb_sys/extensiontask"

GEMSPEC = Gem::Specification.load("tokra.gemspec")

RbSys::ExtensionTask.new("tokra", GEMSPEC) do |ext|
  ext.lib_dir = "lib/tokra"
end

# Sync Tauri JS templates before compile/build
task compile: "sync:tauri"
task build: :compile

# Plugin directories
PLUGINS = Dir["plugins/*"].select { |f| File.directory?(f) }

# Plugin tasks that delegate to each plugin's Rakefile
namespace :plugins do
  desc "Test all plugins"
  task :test do
    PLUGINS.each do |plugin|
      # Each plugin has its own Gemfile. Without an unbundled environment,
      # the inherited BUNDLE_GEMFILE would run the plugin under the root bundle.
      Bundler.with_unbundled_env do
        sh "cd #{plugin} && bundle install --quiet && bundle exec rake test"
      end
    end
  end

  desc "Lint all plugins (RuboCop)"
  task :lint do
    # RuboCop runs from root and includes plugins via config
    # Individual plugin lints can be run from their directories
  end
end

require_relative "tasks/cargo_output"

# rake-compiler runs make, and rb_sys's Makefile runs cargo, without
# looking at what either prints, so this compiles tokra in a child rake and
# fails on any warning in its output (CargoOutput). The gate starts here;
# later compiles are no-ops, and Cargo replays a crate's warnings even then.
# Plugins carry no Rust (ADR 011): ferro-arboard compiles when Bundler
# installs it.
desc "Compile the native extension, failing on any rustc or Cargo warning"
task "compile:strict" do
  CargoOutput.run!(Gem.ruby, "-S", "rake", "compile")
rescue CargoOutput::Failure => e
  abort "❌ #{e.message}"
end

# Import all tasks from the tasks/ directory
Dir.glob("tasks/*.rake").each { |r| import r }

task default: %w[compile:strict lint:fix test lint steep lint:rust package:check]
