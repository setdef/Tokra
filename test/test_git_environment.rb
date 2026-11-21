# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "open3"
require "tmpdir"

# The environment test_helper.rb gives every git a test starts: a commit
# in a test's repository starts no background maintenance, whose lock file
# would come and go while the test deletes the repository.
class TestGitEnvironment < Minitest::Test
  # The variables a git hook passes on, which would point git at the
  # repository whose hook runs these tests.
  GIT_PLACE = %w[GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_PREFIX GIT_COMMON_DIR].to_h { |name| [name, nil] }.freeze

  # Git with no one's own configuration or hooks, and its trace on.
  GIT_TRACED = GIT_PLACE.merge("GIT_CONFIG_GLOBAL" => File::NULL, "GIT_CONFIG_NOSYSTEM" => "1", "GIT_TRACE" => "1").freeze

  def test_a_commit_in_a_tests_repository_starts_no_background_maintenance
    Dir.mktmpdir("git-environment") do |dir|
      git(dir, "init", "--quiet")
      trace = git(dir, "commit", "--quiet", "--allow-empty", "--message", "one")

      refute_match(/maintenance run/, trace)
    end
  end

  # Runs git in +dir+ with its trace on, and answers what it printed.
  private def git(dir, *)
    printed, status = Open3.capture2e(GIT_TRACED, "git", "-c", "user.name=Test", "-c", "user.email=test@example.com",
      *, chdir: dir)
    assert_predicate status, :success?, printed
    printed
  end
end
