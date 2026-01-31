# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

# Tests for Tokra::AppManager
class TestAppManager < Minitest::Test
  def test_app_manager_holds_config_and_webviews
    config = Tokra::Config.new(
      identifier: "com.example.test",
      product_name: "Test App",
      version: "1.0.0"
    )
    webviews = {}

    manager = Tokra::AppManager.new(config:, webviews:)

    assert_equal config, manager.config
    assert_equal webviews, manager.webviews
  end

  def test_config_is_ractor_shareable
    config = Tokra::Config.new(
      identifier: "com.example.test",
      product_name: "Test App",
      version: "1.0.0"
    )

    manager = Tokra::AppManager.new(config:, webviews: {})

    # Config itself is shareable but AppManager holds mutable webviews
    assert Ractor.shareable?(manager.config)
  end
end
