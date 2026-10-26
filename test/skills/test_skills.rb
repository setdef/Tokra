# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "yaml"

# Tests that each project skill follows the Agent Skills specification
# (agentskills.io/specification) and that Claude Code can find it.
class TestSkills < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  SKILLS = Dir.glob(File.join(ROOT, ".agents/skills/*/SKILL.md"))

  private def frontmatter(path)
    text = File.read(path)
    match = text.match(/\A---\n(.*?)\n---\n(.*)\z/m)
    assert match, "#{path} opens with YAML frontmatter"
    [YAML.safe_load(match[1]), match[2]]
  end

  def test_the_three_skills_exist
    assert_equal %w[audit-parity commit-session port-tauri-feature], SKILLS.map { |path| File.basename(File.dirname(path)) }
  end

  def test_each_skill_meets_the_specification
    SKILLS.each do |path|
      meta, body = frontmatter(path)
      name = meta.fetch("name")

      assert_equal File.basename(File.dirname(path)), name, "name matches the directory"
      assert_match(/\A[a-z0-9]+(-[a-z0-9]+)*\z/, name)
      assert_operator name.length, :<=, 64
      assert_includes 1..1024, meta.fetch("description").length
      assert_operator body.lines.size, :<, 500, "#{name} keeps SKILL.md under 500 lines"
    end
  end

  # Each skill stands alone: every relative link, from SKILL.md or its
  # references, resolves to a file inside the same skill.
  def test_each_link_resolves_inside_its_own_skill
    SKILLS.each do |path|
      root = File.dirname(path)
      Dir.glob("**/*.md", base: root).each do |file|
        File.read(File.join(root, file)).scan(/\]\(([^)#]+)\)/).flatten.reject { |link| link.match?(%r{\A[a-z]+://}) }.each do |link|
          target = File.expand_path(link, File.dirname(File.join(root, file)))

          assert target.start_with?("#{root}/"), "#{file} in #{File.basename(root)} links outside the skill: #{link}"
          assert File.exist?(target), "#{file} in #{File.basename(root)} links a missing file: #{link}"
        end
      end
    end
  end

  # Each skill carries its own copy of the parity checklist so it stands
  # alone (Plan 017), and the copies must not drift apart.
  def test_both_parity_checklists_are_identical
    port, audit = %w[port-tauri-feature audit-parity].map do |name|
      File.read(File.join(ROOT, ".agents/skills", name, "references/parity-checklist.md"))
    end

    assert_equal port, audit, "edit both copies of references/parity-checklist.md together"
  end

  def test_claude_code_sees_each_skill_through_a_relative_symlink
    SKILLS.each do |path|
      name = File.basename(File.dirname(path))
      link = File.join(ROOT, ".claude/skills", name)

      assert File.symlink?(link), "#{link} is a symlink"
      assert_equal "../../.agents/skills/#{name}", File.readlink(link)
      assert_equal File.realpath(File.dirname(path)), File.realpath(link)
    end
  end
end
