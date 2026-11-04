# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tokra::Config is Tauri's whole config, at the root where Tauri re-exports
# it (lib.rs:217-237; plan 054, decision 2). Its schema's tests are in
# test/utils/config/.
class TestConfig < Minitest::Test
  def test_config_is_the_utils_config_itself
    assert_same Tokra::Utils::Config::Config, Tokra::Config
  end

  def test_config_takes_tauris_defaults_for_what_it_is_not_given
    config = Tokra::Config.new(identifier: "com.example.test")

    assert_equal "com.example.test", config.identifier
    assert_nil config.product_name
    assert_nil config.version
    assert_empty config.app.windows
  end
end
