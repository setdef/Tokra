# frozen_string_literal: true

# SPDX-FileCopyrightText: 2025 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

require "bundler/gem_tasks"

require "rdoc/task"
RDoc::Task.new do |rdoc|
  rdoc.rdoc_dir = ENV["RDOC_OUTPUT"] || "tmp/rdoc"
end

# Rust extension compilation
require "rb_sys/extensiontask"

GEMSPEC = Gem::Specification.load("tokra.gemspec")

RbSys::ExtensionTask.new("tokra", GEMSPEC) do |ext|
  ext.lib_dir = "lib/tokra"
end

task build: :compile

# Import all tasks from the tasks/ directory
Dir.glob("tasks/*.rake").each { |r| import r }

task default: %w[compile lint:fix test lint steep lint:rust]
