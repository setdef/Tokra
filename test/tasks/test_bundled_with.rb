# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests that every lockfile runs one Bundler that Ruby 4.1 can load (Plan 069).
#
# RubyGems runs the Bundler a lockfile names under BUNDLED WITH. Bundler
# 4.0.11 and older read Pathname::SEPARATOR_PAT (bundler/source/path.rb),
# which Ruby 4.1 removed (ruby a5996718f3), so every bundle command raised
# NameError there. Bundler 4.0.12 reads Pathname#absolute? instead
# (rubygems 67ce6df4c9). One version for every lockfile keeps a plugin's
# from lagging behind the root's.
#
# Each lockfile is read as git's index holds it: the gate installs each
# plugin's bundle before these tests run, and Bundler may write its own
# version into a plugin's lockfile there (Plan 061). vendor/ holds other
# projects' files as they publish them, magnus's lockfile among them (Plan
# 071), which no bundle command of Tokra's reads.
class TestBundledWith < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  FIRST_ON_RUBY_4_1 = Gem::Version.new("4.0.12")

  def test_every_lockfile_names_the_root_lockfiles_bundler
    root = bundled_with("Gemfile.lock")

    lockfiles.each { |path| assert_equal root, bundled_with(path), path }
  end

  def test_the_root_lockfiles_bundler_runs_on_ruby_4_1
    version = bundled_with("Gemfile.lock")

    assert_operator Gem::Version.new(version), :>=, FIRST_ON_RUBY_4_1, "Bundler #{version} reads Pathname::SEPARATOR_PAT"
  end

  # A lockfile that records Bundler's own checksum records it for the
  # Bundler it names, as Bundler writes it; Bundler rewrites one of another
  # version.
  def test_a_lockfiles_bundler_checksum_is_its_bundlers
    lockfiles.each do |path|
      checksummed = indexed(path)[/^CHECKSUMS\n(?:  .*\n)*?  bundler \((\S+)\) sha256=/, 1]
      assert_equal bundled_with(path), checksummed, path if checksummed
    end
  end

  private def lockfiles
    paths = IO.popen(["git", "ls-files", "-z", "--", "*Gemfile.lock", ":!vendor/"], chdir: ROOT, &:read).split("\0")
    refute_empty paths
    paths
  end

  private def bundled_with(path)
    indexed(path)[/^BUNDLED WITH\n\s+(\S+)/, 1] || flunk("#{path} names no Bundler")
  end

  private def indexed(path)
    IO.popen(["git", "show", ":#{path}"], chdir: ROOT, &:read)
  end
end
