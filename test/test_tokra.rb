# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for the Tokra gem top-level module
#
# These tests verify the module structure and basic setup.
# They serve as documentation for gem users about what's available.
class TestTokra < Minitest::Test
  # ==========================================================================
  # Module Structure
  # ==========================================================================

  def test_tokra_module_is_defined
    assert defined?(Tokra), "Tokra module should be defined"
  end

  def test_tokra_native_module_is_defined
    assert defined?(Tokra::Native), "Tokra::Native module should be defined"
  end

  # ==========================================================================
  # Version
  # ==========================================================================

  def test_that_it_has_a_version_number
    refute_nil ::Tokra::VERSION
  end

  def test_version_is_a_string
    assert_kind_of String, ::Tokra::VERSION
  end

  def test_version_is_frozen
    assert ::Tokra::VERSION.frozen?, "VERSION should be frozen"
  end

  def test_version_matches_semver_format
    # Pre-release versions like "0.0.1.pre.1" are valid
    semver_pattern = /\A\d+\.\d+\.\d+(\.(pre|alpha|beta|rc)\.\d+)?\z/
    assert_match semver_pattern, ::Tokra::VERSION,
      "VERSION should match semver format"
  end

  # ==========================================================================
  # Error Class
  # ==========================================================================

  def test_error_class_is_defined
    assert defined?(Tokra::Error), "Tokra::Error should be defined"
  end

  def test_error_inherits_from_standard_error
    assert Tokra::Error < StandardError,
      "Tokra::Error should inherit from StandardError"
  end

  def test_error_can_be_raised_and_rescued
    raised = false
    begin
      raise Tokra::Error, "test message"
    rescue Tokra::Error => e
      raised = true
      assert_equal "test message", e.message
    end
    assert raised, "Should have raised Tokra::Error"
  end
end
