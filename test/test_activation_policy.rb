# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "support/stub_native"

# App#set_activation_policy and Tokra::ActivationPolicy, which Tauri
# defines only on macOS (tauri-runtime src/lib.rs:245-256, tauri
# src/app.rs:1149-1166). Before the loop runs, Tauri hands the policy to
# the runtime, which sets it on tao's event loop (tauri-runtime-wry
# src/lib.rs:3031-3036); App#run here builds that loop, so it hands the
# policy over before running it.
class TestActivationPolicy < Minitest::Test
  MACOS = RbConfig::CONFIG["host_os"].include?("darwin")

  def setup
    StubNative.clear_event
  end

  def teardown
    StubNative.clear_event
  end

  def test_defined_only_on_macos
    assert_equal MACOS, Tokra.const_defined?(:ActivationPolicy)
    assert_equal MACOS, Tokra::App.method_defined?(:set_activation_policy)
    assert_equal MACOS, Tokra::Native::EventLoop.method_defined?(:set_activation_policy)
  end

  def test_the_variants_name_appkits_policies
    skip_unless_macos
    policy = Tokra::ActivationPolicy
    names = [policy::Regular, policy::Accessory, policy::Prohibited].map(&:name)

    assert_equal %w[Regular Accessory Prohibited], names
  end

  # Tauri's ActivationPolicy is a closed enum: no fourth policy exists.
  def test_no_other_policy_can_be_made
    skip_unless_macos

    assert_raises(NoMethodError) { Tokra::ActivationPolicy.new(name: "Background") }
  end

  def test_a_policy_set_in_setup_reaches_the_loop_before_it_runs
    skip_unless_macos
    hook = Ractor.shareable_proc { |app| app.set_activation_policy(Tokra::ActivationPolicy::Prohibited) }
    Tokra::Builder.default.setup(&hook).run(native: StubNative)

    assert_equal [[:set_activation_policy, "Prohibited"], [:run]], StubNative.event_loop_calls
  end

  def test_a_policy_set_before_run_reaches_the_loop
    skip_unless_macos
    app = Tokra::Builder.default.build(native: StubNative)
    app.set_activation_policy(Tokra::ActivationPolicy::Accessory)
    app.run

    assert_equal [[:set_activation_policy, "Accessory"], [:run]], StubNative.event_loop_calls
  end

  def test_the_last_policy_set_wins
    skip_unless_macos
    app = Tokra::Builder.default.build(native: StubNative)
    app.set_activation_policy(Tokra::ActivationPolicy::Accessory)
    app.set_activation_policy(Tokra::ActivationPolicy::Regular)
    app.run

    assert_equal [[:set_activation_policy, "Regular"], [:run]], StubNative.event_loop_calls
  end

  def test_without_a_policy_the_loop_keeps_taos_default
    Tokra::Builder.default.run(native: StubNative)

    assert_equal [[:run]], StubNative.event_loop_calls
  end

  def test_returns_nil
    skip_unless_macos
    app = Tokra::Builder.default.build(native: StubNative)

    assert_nil app.set_activation_policy(Tokra::ActivationPolicy::Prohibited)
  end

  private def skip_unless_macos
    skip "Tauri defines ActivationPolicy only on macOS" unless MACOS
  end
end
