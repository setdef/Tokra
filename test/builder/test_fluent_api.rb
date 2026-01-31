# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/stub_native"

# Tests for Tokra::Builder fluent API chaining.
# Verifies methods return self for method chaining.
class TestBuilderFluentApi < Minitest::Test
  def test_default_creates_new_builder_each_time
    builder1 = Tokra::Builder.default
    builder2 = Tokra::Builder.default
    refute_same builder1, builder2
  end

  def test_invoke_handler_returns_self_for_fluent_chaining
    builder = Tokra::Builder.default
    handler = Ractor.shareable_proc { |_invoke| false }
    result = builder.invoke_handler(&handler)
    assert_same builder, result
  end

  def test_register_uri_scheme_protocol_returns_self
    builder = Tokra::Builder.default
    handler = Ractor.shareable_proc { nil }
    result = builder.register_uri_scheme_protocol("tokra", &handler)
    assert_same builder, result
  end

  def test_register_asynchronous_uri_scheme_protocol_returns_self
    builder = Tokra::Builder.default
    handler = Ractor.shareable_proc { nil }
    result = builder.register_asynchronous_uri_scheme_protocol("tokra", &handler)
    assert_same builder, result
  end

  def test_setup_returns_self_for_fluent_chaining
    builder = Tokra::Builder.default
    hook = Ractor.shareable_proc { nil }
    result = builder.setup(&hook)
    assert_same builder, result
  end

  def test_on_page_load_returns_self_for_fluent_chaining
    builder = Tokra::Builder.default
    hook = Ractor.shareable_proc { nil }
    result = builder.on_page_load(&hook)
    assert_same builder, result
  end

  def test_on_window_event_returns_self_for_fluent_chaining
    builder = Tokra::Builder.default
    hook = Ractor.shareable_proc { nil }
    result = builder.on_window_event(&hook)
    assert_same builder, result
  end

  def test_manage_returns_self_for_fluent_chaining
    builder = Tokra::Builder.default
    result = builder.manage("some state")
    assert_same builder, result
  end

  def test_on_webview_event_is_chainable
    builder = Tokra::Builder.default
    hook = Ractor.shareable_proc { |_webview, _event| :got_it }
    result = builder.on_webview_event(&hook)
    assert_same builder, result
  end

  def test_full_fluent_chain_compiles
    null_hook = Ractor.shareable_proc { nil }
    false_hook = Ractor.shareable_proc { false }
    app = Tokra::Builder.default
      .register_uri_scheme_protocol("app", &null_hook)
      .invoke_handler(&false_hook)
      .setup(&null_hook)
      .on_page_load(&null_hook)
      .on_window_event(&null_hook)
      .build(native: StubNative)

    assert_instance_of Tokra::App, app
  end
end
