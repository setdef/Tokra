# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/autorun"
require "tokra-log"

# Tests for level_for deliberate non-implementation.
#
# Tauri's level_for(module, level) filters by Rust module path.
# Ruby has no equivalent metadata, so we raise NotImplementedError
# with a clear explanation.
class TestLevelFor < Minitest::Test
  def test_level_for_raises_not_implemented_error
    plugin = Tokra::Plugins::Log::Plugin.new({})

    error = assert_raises(NotImplementedError) do
      plugin.level_for("SomeModule", :warn)
    end

    assert_match(/Rust module path/, error.message)
  end

  def test_level_for_error_suggests_filter_alternative
    plugin = Tokra::Plugins::Log::Plugin.new({})

    error = assert_raises(NotImplementedError) { plugin.level_for("Foo", :info) }

    assert_match(/filter/, error.message)
  end
end
