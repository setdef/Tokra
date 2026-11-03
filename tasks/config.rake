# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "English"
require "json"
require "rbconfig"
require_relative "cargo_output"

# Regenerates the config fixtures' answer key from Tauri's own crates
# (plan 054, "The fixture generator").
#
# The generator under test/fixtures/config/generator is its own Cargo
# workspace, built with --locked against a lock seeded from
# vendor/tauri/Cargo.lock. Building it compiles tauri-codegen and
# tauri-utils with their build features, so the gate never does: no
# CARGO_WORKSPACES entry names it, and only rust:fmt reads its source. Run
# this after changing a case or bumping the submodule, and commit the
# expected.jsonl files it rewrites.
#
# It needs vendor/tauri checked out at the pinned commit (git submodule
# update --init), and either network access or a ~/.cargo registry that
# already holds every crate the lock names.
namespace :config do
  desc "Regenerate test/fixtures/config's expected.jsonl from Tauri's crates (not in the gate)"
  task :fixtures do
    root = "test/fixtures/config"
    unless File.directory?("vendor/tauri/crates/tauri-codegen")
      abort "❌ vendor/tauri is not checked out. Run: git submodule update --init"
    end
    manifest = "#{root}/generator/Cargo.toml"
    target_dir = File.expand_path("tmp/config-fixtures")
    cargo = ["--locked", "--manifest-path", manifest, "--target-dir", target_dir]
    # The build without Tauri's optional formats answers for phase 1, the
    # one with them for phase 2; each line names its build.
    builds = [[], ["--features", "formats"]]
    answers = builds.flat_map do |features|
      CargoOutput.run!("cargo", "clippy", *cargo, *features, "--all-targets", "--", "-D", "warnings")
      CargoOutput.run!("cargo", "build", *cargo, *features)
      output = IO.popen([File.join(target_dir, "debug", "tokra-config-fixtures#{RbConfig::CONFIG['EXEEXT']}"), root], &:read)
      abort "❌ the config fixture generator failed" unless $CHILD_STATUS.success?

      output.lines
    end
    answers.group_by { |line| JSON.parse(line).fetch("case") }.each do |name, lines|
      File.write(File.join(root, name, "expected.jsonl"), lines.join)
      puts "#{root}/#{name}/expected.jsonl: #{lines.size} answers"
    end
  rescue CargoOutput::Failure => e
    abort "❌ #{e.message}"
  end
end
