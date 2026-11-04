# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "support/stub_native"
require_relative "support/test_app"

# Builder#build and Builder#run take the app's Context, as Tauri's
# Builder::build and Builder::run do (app.rs:2094, 2298-2302), and the
# window settings ADR 004 invented are gone: the config holds them (ADR 014
# §1; plan 054, decision 12).
class TestBuilder < Minitest::Test
  def setup
    StubNative.clear_event
  end

  def teardown
    StubNative.clear_event
  end

  def test_build_takes_the_context_and_the_app_holds_its_config_and_package_info
    context = build_test_context(config: { "version" => "1.2.0" })
    app = Tokra::Builder.default.build(context, native: StubNative)

    assert_instance_of Tokra::App, app
    assert_same context.config, app.config
    assert_same context.package_info, app.package_info
    assert_equal "1.2.0", app.package_info.version
    assert_same context.config, app.handle.config
    assert_same context.package_info, app.handle.package_info
  end

  def test_build_needs_a_context
    assert_raises(ArgumentError) { Tokra::Builder.default.build(native: StubNative) }
    error = assert_raises(TypeError) { Tokra::Builder.default.build({ "identifier" => "x" }, native: StubNative) }
    assert_equal "wrong argument type Hash (expected Tokra::Context)", error.message
  end

  def test_run_takes_the_context_and_opens_its_windows
    context = build_test_context(title: "From the config", width: 640, height: 480)
    events = []
    Tokra::Builder.default.run(context, native: StubNative) { |_handle, event| events << event.class }

    assert_equal [Tokra::RunEvent::Ready, Tokra::RunEvent::Exit], events
    window = StubNative.windows.first
    assert_equal "From the config", window.title
    assert_equal [640.0, 480.0], window.size
  end

  def test_run_needs_a_context
    assert_raises(ArgumentError) { Tokra::Builder.default.run(native: StubNative) }
  end

  # Their settings are app.windows[].title, .width, .height, and
  # app.withGlobalTauri in the config (ADR 014 §1).
  def test_the_window_settings_tauri_does_not_have_are_gone
    builder = Tokra::Builder.default
    assert_raises(NoMethodError) { builder.title("My App") }
    assert_raises(NoMethodError) { builder.size(800, 600) }
    assert_raises(NoMethodError) { builder.with_global_tauri }
  end
end
