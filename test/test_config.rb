# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

# Tests for Tokra::Config (Tauri parity).
#
# Tauri's Config contains: identifier, product_name, version, app, build, bundle, plugins.
# Tokra's MVP subset: identifier, product_name, version.
class TestConfig < Minitest::Test
  def test_config_is_data_define_with_required_fields
    config = Tokra::Config.new(
      identifier: "com.example.test",
      product_name: "Test App",
      version: "1.0.0"
    )

    assert_equal "com.example.test", config.identifier
    assert_equal "Test App", config.product_name
    assert_equal "1.0.0", config.version
  end

  def test_config_is_frozen_and_ractor_shareable
    config = Tokra::Config.new(
      identifier: "com.example.test",
      product_name: "Test App",
      version: "1.0.0"
    )

    assert config.frozen?
    assert Ractor.shareable?(config)
  end
end
