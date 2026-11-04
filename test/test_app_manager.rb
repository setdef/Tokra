# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "support/test_app"

# Tests for Tokra::AppManager, which holds what Tauri's AppManager takes
# from the context: the config, the package information, and the pattern
# (manager/mod.rs:249-322).
class TestAppManager < Minitest::Test
  def test_app_manager_holds_the_contexts_config_package_info_and_pattern
    context = build_test_context
    webviews = {}

    manager = build_test_manager(context, webviews:)

    assert_same context.config, manager.config
    assert_same context.package_info, manager.package_info
    assert_same context.pattern, manager.pattern
    assert_equal true, manager.dev
    assert_same webviews, manager.webviews
  end

  def test_config_is_ractor_shareable
    manager = build_test_manager

    # Config itself is shareable but AppManager holds mutable webviews
    assert Ractor.shareable?(manager.config)
    assert Ractor.shareable?(manager.package_info)
  end
end
