# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "tokra"

require "minitest/autorun"
require "minitest/mock"

# After a commit or a fetch, git starts its maintenance in the background
# (git maintenance run --auto --detach), which takes a lock file in the
# repository. A test that makes a repository deletes it moments later, and
# the delete fails when that file comes or goes under it. So no git a test
# starts runs maintenance: the setting goes after whatever the environment
# already holds.
git_settings = Integer(ENV.fetch("GIT_CONFIG_COUNT", "0"))
ENV.update(
  "GIT_CONFIG_COUNT" => (git_settings + 1).to_s,
  "GIT_CONFIG_KEY_#{git_settings}" => "maintenance.auto",
  "GIT_CONFIG_VALUE_#{git_settings}" => "false"
)
