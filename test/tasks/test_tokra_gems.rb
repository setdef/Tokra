# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../../tasks/bump"
require_relative "../../tasks/tokra_gems"

# Tests that TOKRA_GEMS describes this repository's gems as they are, so
# rake bump:<gem>:* and release:<gem>:* find every file they write.
class TestTokraGems < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def test_every_gemspec_in_the_repository_has_an_entry
    gemspecs = IO.popen(["git", "ls-files", "--", "*.gemspec", chdir: ROOT], &:read).lines.map(&:chomp)
      .reject { |path| path.start_with?("vendor/", "test/") }

    assert_equal gemspecs.sort, TOKRA_GEMS.map { |gem| gem.path(gem.gemspec) }.sort
  end

  def test_tokra_goes_first_and_is_the_only_core_gem
    assert_equal ["tokra"], TOKRA_GEMS.select(&:core?).map(&:name)
    assert_predicate TOKRA_GEMS.first, :core?
  end

  def test_each_version_file_is_the_one_its_gemspec_loads
    TOKRA_GEMS.each do |gem|
      spec = Gem::Specification.load(File.join(ROOT, gem.path(gem.gemspec)))

      assert_equal spec.version, GemVersion.parse(gem.written_version(ROOT)).to_gem_version, gem.name
    end
  end

  def test_each_gem_bundles_itself_at_its_version
    TOKRA_GEMS.each do |gem|
      lock = File.read(File.join(ROOT, gem.path("Gemfile.lock")))

      assert_match(/^    #{Regexp.escape(gem.name)} \(#{Regexp.escape(GemVersion.parse(gem.written_version(ROOT)).rubygems)}\)$/, lock, gem.name)
    end
  end

  # A tokra bump moves each plugin's floor, so each must have one to move.
  def test_each_plugin_bounds_tokra_with_a_floor_its_lockfile_records
    TOKRA_GEMS.reject(&:core?).each do |gem|
      floor = File.read(File.join(ROOT, gem.path(gem.gemspec)))[/^\s*spec\.add_dependency "tokra", "~> ([^"]+)"$/, 1]

      refute_nil floor, gem.name
      assert_includes File.read(File.join(ROOT, gem.path("Gemfile.lock"))), "      tokra (~> #{floor})\n", gem.name
    end
  end

  def test_tokras_crate_and_its_lock_entry_exist
    gem = TOKRA_GEMS.first

    assert_match(/^\[package\]\nname = "tokra"\nversion = "[^"]+"$/, File.read(File.join(ROOT, gem.crate, "Cargo.toml")))
    assert_match(/^name = "tokra"\nversion = "[^"]+"$/, File.read(File.join(ROOT, "Cargo.lock")))
  end

  def test_tokras_generated_files_come_from_its_prepare_commands
    gem = TOKRA_GEMS.first

    assert_equal ["lib/tokra/js/*"], gem.generated
    assert_equal [
      ["git", "submodule", "update", "--init", "--reference", "/repo/vendor/tauri", "vendor/tauri"],
      %w[bundle exec rake sync:tauri],
    ], gem.prepare.call("/repo")
    TOKRA_GEMS.reject(&:core?).each { |plugin| assert_empty plugin.prepare.call("/repo"), plugin.name }
  end

  # A bump releases the gem's own CHANGELOG and moves its Unreleased link.
  def test_each_gem_ships_a_changelog_of_its_own_that_a_bump_can_release
    TOKRA_GEMS.each do |gem|
      changelog = File.read(File.join(ROOT, gem.path(gem.changelog)))
      spec = Gem::Specification.load(File.join(ROOT, gem.path(gem.gemspec)))

      assert_match(/^## \[Unreleased\]$/, changelog, gem.name)
      assert_match(Changelog::UNRELEASED_LINK, changelog, gem.name)
      assert_includes spec.files, gem.changelog, gem.name
      assert_equal "https://github.com/setdef/Tokra/blob/trunk/#{gem.path(gem.changelog)}", spec.metadata["changelog_uri"], gem.name
    end
  end

  # https://tokra.app redirects to https://www.tokra.app.
  def test_every_gem_names_the_same_homepage
    TOKRA_GEMS.each do |gem|
      spec = Gem::Specification.load(File.join(ROOT, gem.path(gem.gemspec)))

      assert_equal "https://www.tokra.app", spec.homepage, gem.name
    end
  end

  # Bundler's release would tag v0.1.0 for every gem, so no Rakefile loads
  # it; tasks/releases.rake releases each gem under a tag named for it.
  def test_no_rakefile_loads_bundlers_gem_tasks
    rakefiles = IO.popen(["git", "ls-files", "--", "Rakefile", "plugins/*/Rakefile", chdir: ROOT], &:read).lines.map(&:chomp)

    assert_equal 1 + TOKRA_GEMS.count { |gem| !gem.core? }, rakefiles.size
    rakefiles.each { |rakefile| refute_match(%r{^require "bundler/gem_tasks"}, File.read(File.join(ROOT, rakefile)), rakefile) }
  end

  def test_names_and_paths
    shortcut = TOKRA_GEMS.find { |gem| gem.short_name == "global-shortcut" }

    assert_equal "tokra-global-shortcut", shortcut.name
    assert_equal "plugins/global-shortcut/lib/tokra/plugins/global_shortcut/version.rb", shortcut.path(shortcut.version_file)
    assert_equal "tokra-global-shortcut/v", shortcut.tag_prefix
    assert_equal "CHANGELOG.md", TOKRA_GEMS.first.path("CHANGELOG.md")
  end
end
