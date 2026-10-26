# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/notification_test"
require "digest"

# The plugin's registration, routing, init script, and permission
# commands, through the real plugin on a real handle.
class TestCommands < Minitest::Test
  include NotificationTest

  # The upstream file's checksum, recorded from git show
  # d4613ff0:plugins/notification/src/init-iife.js.
  UPSTREAM_INIT_SCRIPT_SHA256 = "31c05e7f79a905c4319535d11919dc44aedb7b06dfca03189d52f5721dd32451"

  # Tauri's plugin name (lib.rs:223).
  def test_the_plugin_is_named_notification
    assert_equal "notification", build_plugin.name
  end

  # The setup closure manages the desktop Notification (lib.rs:233-240),
  # and NotificationExt reaches it from every manager (lib.rs:210-219).
  def test_registering_manages_a_notification_every_manager_reaches
    app = build_app
    build_plugin(app)

    notification = app.handle.notification
    assert_instance_of Notification::Notification, notification
    assert_same app.handle, notification.app_handle
    assert_same notification, app.handle.state(Notification::Notification)
    assert_instance_of Notification::NotificationBuilder, notification.builder
  end

  # Only notify, request_permission, and is_permission_granted are in the
  # desktop handler (lib.rs:224-228); the router rejects the rest.
  def test_mobile_commands_are_left_for_the_router
    app = build_app
    plugin = build_plugin(app)
    %w[
      register_action_types
      register_listener
      registerListener
      cancel
      get_pending
      remove_active
      get_active
      check_permissions
      show
      batch
      list_channels
      listChannels
      delete_channel
      create_channel
      permission_state
].each do |command|
      invoke, = build_invoke(app.handle, command)
      refute plugin.extend_api(invoke), "#{command} is mobile-only in Tauri"
    end
  end

  # The init script is Tauri's file with __TEMPLATE_windows__ replaced by
  # whether this is Windows (lib.rs:229-232).
  def test_the_init_script_is_tauris_file_with_the_platform_filled_in
    script = build_plugin.initialization_script
    upstream = File.read(File.expand_path("../lib/tokra/plugins/notification/init-iife.js", __dir__))
    assert_equal UPSTREAM_INIT_SCRIPT_SHA256, Digest::SHA256.hexdigest(upstream)
    windows = Gem.win_platform? ? "true" : "false"
    assert_equal upstream.gsub("__TEMPLATE_windows__", windows), script
    assert_includes script, "window.Notification.permission||#{windows}?await Promise.resolve(\"granted\""
    assert_includes script, "plugin:notification|notify"
  end

  # Desktop permission is always granted (desktop.rs:61-67), which the
  # command reports as true (commands.rs:9-20).
  def test_permission_is_granted_on_desktop
    assert_equal [true, true], answer("is_permission_granted")
    assert_equal [true, "granted"], answer("request_permission")
    notification = build_app.handle.tap { |handle| build_plugin_on(handle) }.notification
    assert_same Tokra::PermissionState::Granted, notification.permission_state
    assert_same Tokra::PermissionState::Granted, notification.request_permission
    assert_same Tokra::PermissionState, Notification::PermissionState
  end

  # A denied or unasked state maps to false and null (commands.rs:15-19).
  def test_is_permission_granted_maps_each_state
    {
      Tokra::PermissionState::Granted => true,
      Tokra::PermissionState::Denied => false,
      Tokra::PermissionState::Prompt => nil,
      Tokra::PermissionState::PromptWithRationale => nil,
    }.each do |state, expected|
      app = build_app
      invoke, answers = build_invoke(app.handle, "is_permission_granted")
      notification = Struct.new(:permission_state).new(state)
      Notification::Commands.is_permission_granted(invoke, notification)
      assert_equal [true, expected], answers.pop(timeout: 1), state.to_s
    end
  end

  # Tauri's CommandItem rejects a missing argument the command requires
  # (tauri ipc/command.rs:97-102).
  def test_notify_without_options_rejects
    assert_equal "invalid args `options` for command `notify`: command notify missing required key options",
      rejection("notify", {})
  end

  # notify resolves null as soon as the notification is on its way
  # (commands.rs:30-39), whether or not a server takes it.
  # On macOS a send changes this process's bundle identifier and may show
  # the notification, so the macOS tests send from a child instead
  # (test_macos_notifications.rb).
  def test_notify_resolves_null
    skip "macOS sends only from a child process" if PLATFORM == :macos
    assert_equal [true, nil], answer("notify", { "options" => { "title" => TITLE, "body" => "resolves" } })
  end

  def test_a_bad_option_rejects_with_serdes_message
    assert_equal "invalid args `options` for command `notify`: invalid type: integer `1`, expected a string",
      notify_rejection({ "title" => 1 })
  end

  # Only an argument that does not read rejects here: an ArgumentError
  # from a bug reaches the router, which logs it before it rejects
  # (plan 026, decision 7).
  def test_an_argument_error_from_a_bug_is_not_taken_for_a_bad_argument
    app = build_app
    plugin = build_plugin(app)
    app.handle.notification.define_singleton_method(:permission_state) { raise ArgumentError, "a bug" }
    invoke, = build_invoke(app.handle, "is_permission_granted")

    assert_equal "a bug", assert_raises(ArgumentError) { plugin.extend_api(invoke) }.message
  end

  private def build_plugin_on(handle)
    handle.plugin(Notification::Plugin.new(handle))
  end
end
