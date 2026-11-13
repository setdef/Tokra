# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "date"
require "fileutils"
require "tmpdir"
require_relative "../../tasks/changelog"

# Tests how a release rewrites a gem's CHANGELOG.md, links included.
class TestChangelog < Minitest::Test
  HEAD = "# Changelog\n\nReleases are tagged `tokra-demo/vX.Y.Z`.\n\n"
  REPO = "https://github.com/setdef/Tokra"
  DATE = Date.new(2026, 10, 25)

  def setup
    @dir = Dir.mktmpdir("changelog")
    @path = File.join(@dir, "CHANGELOG.md")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  private def release(content, version)
    File.write(@path, content)
    Changelog.new(@path, tag_prefix: "tokra-demo/v").release(version, date: DATE)
    File.read(@path)
  end

  def test_the_first_release_links_its_tag
    written = release("#{HEAD}## [Unreleased]\n\n### Added\n\n- A thing.\n\n[Unreleased]: #{REPO}/commits/trunk/plugins/demo\n", "0.1.0")

    assert_equal <<~MARKDOWN, written
      #{HEAD.chomp}
      ## [Unreleased]

      ## [0.1.0] - 2026-10-25

      ### Added

      - A thing.

      [Unreleased]: #{REPO}/compare/tokra-demo/v0.1.0...HEAD
      [0.1.0]: #{REPO}/releases/tag/tokra-demo/v0.1.0
    MARKDOWN
  end

  def test_a_later_release_compares_with_the_one_before
    content = "#{HEAD}## [Unreleased]\n\n- Second.\n\n## [0.1.0] - 2026-10-01\n\n- First.\n\n" \
      "[Unreleased]: #{REPO}/compare/tokra-demo/v0.1.0...HEAD\n[0.1.0]: #{REPO}/releases/tag/tokra-demo/v0.1.0\n"

    written = release(content, "0.1.1")

    assert_includes written, "## [Unreleased]\n\n## [0.1.1] - 2026-10-25\n\n- Second.\n\n## [0.1.0] - 2026-10-01\n\n- First.\n"
    assert_includes written, "[Unreleased]: #{REPO}/compare/tokra-demo/v0.1.1...HEAD\n" \
      "[0.1.1]: #{REPO}/compare/tokra-demo/v0.1.0...tokra-demo/v0.1.1\n[0.1.0]: #{REPO}/releases/tag/tokra-demo/v0.1.0\n"
  end

  # tokra shipped 0.0.1.pre.1 and pre.2 under tags named v..., and its
  # CHANGELOG has no section for either; its Unreleased link starts at the
  # last of them, so the first release compares from there.
  def test_a_release_compares_from_where_the_unreleased_link_did
    content = "#{HEAD}## [Unreleased]\n\n- Since pre.2.\n\n[Unreleased]: #{REPO}/compare/v0.0.1.pre.2...HEAD\n"

    written = release(content, "0.1.0")

    assert_includes written, "[Unreleased]: #{REPO}/compare/tokra-demo/v0.1.0...HEAD\n" \
      "[0.1.0]: #{REPO}/compare/v0.0.1.pre.2...tokra-demo/v0.1.0\n"
  end

  def test_nothing_to_release_is_refused_and_the_file_kept
    content = "#{HEAD}## [Unreleased]\n\n### Added\n\n[Unreleased]: #{REPO}/commits/trunk\n"

    error = assert_raises(Changelog::Failure) { release(content, "0.1.0") }

    assert_includes error.message, "nothing under Unreleased"
    assert_equal content, File.read(@path)
  end

  def test_a_changelog_without_an_unreleased_link_is_refused
    error = assert_raises(Changelog::Failure) { release("#{HEAD}## [Unreleased]\n\n- A thing.\n", "0.1.0") }

    assert_includes error.message, "no [Unreleased]: link"
  end

  def test_released_finds_a_versions_section
    File.write(@path, "#{HEAD}## [Unreleased]\n\n## [0.1.0.pre.2] - 2026-10-25\n\n- A thing.\n")
    changelog = Changelog.new(@path, tag_prefix: "tokra-demo/v")

    assert changelog.released?("0.1.0.pre.2")
    refute changelog.released?("0.1.0")
  end
end
