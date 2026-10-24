# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "tmpdir"
require "rubygems/package"
require_relative "support/stub_native"

# Tests that the built gem carries what an installed app needs.
#
# lib/tokra/js/ is generated (rake sync:tauri) and gitignored, so the
# gemspec adds it back by hand; a file it misses raises LoadError the first
# time an installed app runs. The native crate must also compile on its own:
# an installed gem has no repository workspace to inherit lints from.
class TestGemPackage < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def self.packaged_files
    @packaged_files ||= Dir.mktmpdir do |dir|
      gem_path = File.join(dir, "tokra.gem")
      output = IO.popen(["gem", "build", "tokra.gemspec", "--output", gem_path], chdir: ROOT,
        err: [:child, :out], &:read)
      raise "gem build failed:\n#{output}" unless File.exist?(gem_path)

      Gem::Package.new(gem_path).contents
    end
  end

  private def packaged_files = self.class.packaged_files

  # Every script a running app reads through Native.load_js_template,
  # recorded from a real App with every optional script switched on.
  private def scripts_an_app_loads
    loaded = []
    original = Tokra::Native.method(:load_js_template)
    recorder = lambda do |name|
      loaded << name
      original.call(name)
    end
    Tokra::Native.stub(:load_js_template, recorder) do
      StubNative.inject_event(nil)
      Tokra::Builder.default.with_global_tauri.build(native: StubNative).run
    end
    loaded.uniq + ["emit.js.erb"] # emit_js_script memoizes its template
  ensure
    StubNative.clear_event
  end

  def test_every_script_the_app_loads_is_packaged
    scripts = scripts_an_app_loads
    assert_includes scripts, "bundle.global.js", "with_global_tauri loads the API bundle"
    assert_includes scripts, "process-ipc-message-fn.js"

    scripts.each do |name|
      assert_includes packaged_files, "lib/tokra/js/#{name}", "#{name} is loaded at runtime"
    end
  end

  def test_every_vendored_script_is_packaged
    vendored = Dir.children(File.join(ROOT, "lib/tokra/js")).map { |name| "lib/tokra/js/#{name}" }
    refute_empty vendored, "run rake sync:tauri first"

    assert_empty vendored - packaged_files
  end

  def test_packaged_crate_does_not_inherit_from_a_workspace
    manifests = packaged_files.select { |path| File.basename(path) == "Cargo.toml" }

    assert_equal ["ext/tokra/Cargo.toml"], manifests,
      "the repository workspace names crates this gem does not ship"
    manifest = File.read(File.join(ROOT, "ext/tokra/Cargo.toml"))
    refute_match(/^\s*workspace\s*=\s*true/, manifest, "an installed gem has no workspace to inherit from")
    assert_includes manifest, "[lints.clippy]", "the crate states its own lints"
  end
end
