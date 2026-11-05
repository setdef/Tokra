# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "support/stub_native"
require_relative "support/test_app"

# app.enableGTKAppId: on Linux and the BSDs, Tauri's Builder::build hands
# the config's identifier to the runtime as the GTK application id when the
# flag is on (app.rs:2122-2133), and tauri-runtime-wry gives it to tao's
# event loop builder (lib.rs:2779-2790). Tokra builds its loop in App#run.
class TestGtkAppId < Minitest::Test
  Target = Tokra::Utils::Platform::Target
  ENABLED = { "app" => { "enableGTKAppId" => true } }.freeze

  def test_the_identifier_is_the_app_id_on_linux_when_enabled
    config = build_test_context(config: ENABLED).config

    assert_equal TestApp::IDENTIFIER, Tokra::App.gtk_app_id(config, Target::Linux)
  end

  def test_there_is_no_app_id_unless_enabled
    assert_nil Tokra::App.gtk_app_id(build_test_context.config, Target::Linux)
  end

  # Tauri compiles the field only for Linux and the BSDs, which Tokra's
  # Linux target covers (plan 054, decision 2).
  def test_there_is_no_app_id_off_linux
    config = build_test_context(config: ENABLED).config

    assert_nil Tokra::App.gtk_app_id(config, Target::MacOS)
    assert_nil Tokra::App.gtk_app_id(config, Target::Windows)
  end

  # Linux stands in for this platform while the app runs, so the loop's
  # id is checked everywhere; nothing else App#run does reads the target.
  def test_run_builds_the_loop_with_the_app_id
    app = build_test_app(config: ENABLED)
    Target.stub(:current, Target::Linux) { app.run }

    assert_equal [TestApp::IDENTIFIER], StubNative.event_loop_app_ids
  end

  def test_run_builds_the_loop_without_an_app_id_by_default
    app = build_test_app
    Target.stub(:current, Target::Linux) { app.run }

    assert_equal [nil], StubNative.event_loop_app_ids
  end

  def test_run_builds_the_loop_with_this_platforms_app_id
    build_test_app(config: ENABLED).run
    expected = (Target.current == Target::Linux) ? [TestApp::IDENTIFIER] : [nil]

    assert_equal expected, StubNative.event_loop_app_ids
  end

  # *Deviation*: GLib refuses an id like this one, and Tauri would hand
  # gtk_application_new's NULL to the loop; Tokra raises first. Linux only,
  # where the native loop reads the id; no loop is built.
  def test_the_native_loop_refuses_an_id_glib_refuses
    skip "the GTK application id is read only on Linux and the BSDs" unless Target.current == Target::Linux

    error = assert_raises(ArgumentError) { Tokra::Native::EventLoop.new("not-an-application-id") }
    assert_equal 'invalid GTK application id: "not-an-application-id"', error.message
    error = assert_raises(ArgumentError) { Tokra::Native::EventLoop.new("com.example.a\0b") }
    assert_equal 'invalid GTK application id: "com.example.a\\0b"', error.message
  end
end
