# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/dialog_test"
require "digest"

# The plugin's commands up to the dialog: registration, routing, and the
# argument checks Tauri's serde deserialization makes, each rejecting with
# Tauri's message before any dialog opens.
class TestCommands < Minitest::Test
  include DialogTest

  # The upstream file's checksum, recorded from git show
  # d4613ff0:plugins/dialog/src/init-iife.js.
  UPSTREAM_INIT_SCRIPT_SHA256 = "b27eafca0c2bc126b4954434e03b5d887b16fa486ded2dbe6f329c3e264f1ecc"

  # Tauri's plugin name (lib.rs:187) and the commands it registers
  # (lib.rs:196-202).
  def test_the_plugin_is_named_dialog
    assert_equal "dialog", build_plugin.name
  end

  def test_registering_manages_a_dialog_every_manager_reaches
    app = build_app
    build_plugin(app)

    dialog = app.handle.dialog
    assert_instance_of Dialog::Dialog, dialog
    assert_same app.handle, dialog.app_handle
    assert_same dialog, app.handle.state(Dialog::Dialog)
  end

  def test_an_unknown_command_is_left_for_the_router
    app = build_app
    invoke, = build_invoke(app.handle, "pick")
    refute build_plugin(app).extend_api(invoke)
  end

  # The plugin's init script replaces alert and confirm with the plugin's
  # commands (lib.rs:189-193), from Tauri's own file, unchanged.
  def test_the_init_script_is_tauris_file_unchanged
    script = build_plugin.initialization_script
    # SHA-256 of plugins/dialog/src/init-iife.js at plugins-workspace d4613ff0.
    assert_equal UPSTREAM_INIT_SCRIPT_SHA256, Digest::SHA256.hexdigest(script)
    assert_includes script, 'window.alert=function(i){n("plugin:dialog|message",{message:i.toString()})}'
    assert_includes script, 'window.confirm=async function(i){return await n("plugin:dialog|confirm"'
  end

  # Tauri's CommandItem rejects a missing argument the command requires
  # (tauri ipc/command.rs:97-102).
  def test_a_missing_required_argument_rejects
    assert_equal "invalid args `options` for command `open`: command open missing required key options",
      rejection("open", {})
    assert_equal "invalid args `options` for command `save`: command save missing required key options",
      rejection("save", {})
    %w[message ask confirm].each do |command|
      assert_equal "invalid args `message` for command `#{command}`: command #{command} missing required key message",
        rejection(command, {})
    end
  end

  def test_options_that_are_not_an_object_reject
    assert_equal "invalid args `options` for command `open`: invalid type: string \"x\", expected struct OpenDialogOptions",
      rejection("open", { "options" => "x" })
    assert_equal "invalid args `options` for command `save`: invalid type: null, expected struct SaveDialogOptions",
      rejection("save", { "options" => nil })
  end

  def test_each_open_option_checks_its_type
    {
      { "title" => 1 } => "invalid type: integer `1`, expected a string",
      { "multiple" => "yes" } => "invalid type: string \"yes\", expected a boolean",
      { "directory" => nil } => "invalid type: null, expected a boolean",
      { "recursive" => 1.5 } => "invalid type: floating point `1.5`, expected a boolean",
      { "defaultPath" => [] } => "invalid type: sequence, expected path string",
      { "canCreateDirectories" => {} } => "invalid type: map, expected a boolean",
      { "filters" => nil } => "invalid type: null, expected a sequence",
      { "filters" => [1] } => "invalid type: integer `1`, expected struct DialogFilter",
      { "filters" => [{ "extensions" => [] }] } => "missing field `name`",
      { "filters" => [{ "name" => "Text" }] } => "missing field `extensions`",
      { "filters" => [{ "name" => "Text", "extensions" => [true] }] } => "invalid type: boolean `true`, expected a string",
      { "pickerMode" => "photo" } =>
        "unknown variant `photo`, expected one of `document`, `media`, `image`, `video`",
      { "fileAccessMode" => 2 } => "invalid type: integer `2`, expected string or map",
      # serde's OneOf names two variants with "or" (de/mod.rs:2337-2355).
      { "fileAccessMode" => "copied" } => "unknown variant `copied`, expected `copy` or `scoped`",
    }.each do |options, message|
      assert_equal "invalid args `options` for command `open`: #{message}",
        rejection("open", { "options" => options }), options.inspect
    end
  end

  # serde_derive stops at the first bad field it reads; missing fields
  # come after, in declaration order.
  def test_the_first_bad_option_wins
    assert_equal "invalid args `options` for command `open`: invalid type: integer `2`, expected a boolean",
      rejection("open", { "options" => { "multiple" => 2, "title" => 1 } })
    assert_equal "invalid args `options` for command `open`: missing field `name`",
      rejection("open", { "options" => { "filters" => [{}] } })
  end

  # Only an argument that does not read rejects here: an ArgumentError
  # from a bug reaches the router, which logs it before it rejects
  # (plan 026, decision 7).
  def test_an_argument_error_from_a_bug_is_not_taken_for_a_bad_argument
    app = build_app
    plugin = build_plugin(app)
    app.handle.define_singleton_method(:dialog) { raise ArgumentError, "a bug" }
    invoke, = build_invoke(app.handle, "message", { "message" => "m" })

    assert_equal "a bug", assert_raises(ArgumentError) { plugin.extend_api(invoke) }.message
  end

  # A failure after the arguments, here ferro-rfd refusing a filter name
  # with a NUL byte as the main thread builds the dialog, still settles the
  # invoke: the worker rejects with the message (plan 023, decision 2).
  def test_a_failure_opening_the_dialog_rejects
    options = { "filters" => [{ "name" => "a\u0000b", "extensions" => ["txt"] }] }
    assert_equal [false, "string contains null byte"], pumped_answer("open", { "options" => options })
    assert_equal [false, "string contains null byte"], pumped_answer("save", { "options" => options })
  end

  # A command that cannot reach the main thread, because the event loop has
  # ended, rejects with the runtime's message instead of leaving the invoke
  # and its worker waiting (plan 023, decision 2).
  def test_a_command_after_the_loop_ended_rejects
    { "open" => { "options" => {} }, "save" => { "options" => {} }, "message" => { "message" => "m" } }
      .each do |command, payload|
        app = build_app
        plugin = build_plugin(app)
        app.handle.runtime_context.close
        invoke, answers = build_invoke(app.handle, command, payload)
        plugin.extend_api(invoke)
        assert_equal [false, Tokra::Error::Runtime.new(Tokra::Error::Runtime::FAILED_TO_SEND_MESSAGE).message], answers.pop(timeout: 2), command
      end
  end

  # A start already queued when the loop ends is dropped unanswered; the
  # command still rejects (RuntimeContext#close closes a getter's reply).
  # The window answers its handle at once here, so the start is the one
  # task queued; the next test lets the loop end during that read.
  def test_a_command_whose_start_the_ending_loop_drops_rejects
    { "open" => { "options" => {} }, "ask" => { "message" => "m" } }.each do |command, payload|
      app = build_app
      plugin = build_plugin(app)
      invoke, answers = build_invoke(app.handle, command, payload)
      invoke.webview.window.define_singleton_method(:window_handle) { raise Tokra::RawWindowHandle::HandleError::Unavailable }
      plugin.extend_api(invoke)
      sleep 0.2
      app.handle.runtime_context.close
      assert_equal [false, Tokra::Error::Runtime.new(Tokra::Error::Runtime::FAILED_TO_RECEIVE_MESSAGE).message], answers.pop(timeout: 2), command
    end
  end

  # Tauri parents the open dialog only under cfg(any(windows, target_os =
  # "macos")) (commands.rs:129-132); save and the message commands always.
  # The real windows check what follows: the portal call on Linux, the
  # sheet on macOS (test_dialog_window.rb).
  def test_open_has_a_parent_on_windows_and_macos_only
    assert_equal %i[windows macos].include?(PLATFORM), Dialog::Commands::OPEN_HAS_PARENT
  end

  # The parent's handle is a getter of its own, ahead of the start. When
  # the loop ends while it waits, the window is no parent, as Tauri ignores
  # a parent whose handle fails, and the start that follows cannot reach
  # the loop, so the command rejects with the runtime's message.
  def test_a_command_whose_parent_read_the_ending_loop_drops_rejects
    { "save" => { "options" => {} }, "message" => { "message" => "m" } }.each do |command, payload|
      app = build_app
      plugin = build_plugin(app)
      invoke, answers = build_invoke(app.handle, command, payload)
      plugin.extend_api(invoke)
      sleep 0.2
      app.handle.runtime_context.close
      assert_equal [false, Tokra::Error::Runtime.new(Tokra::Error::Runtime::FAILED_TO_SEND_MESSAGE).message],
        answers.pop(timeout: 2), command
    end
  end

  # serde_json describes a value through ryu and Rust's Debug: floats in
  # their shortest form, integers past u64 as floats, and every character
  # Debug escapes. The messages are the plan 026 oracle's.
  def test_values_are_described_as_serde_json_describes_them
    {
      { "multiple" => 1e16 } => "invalid type: floating point `1e16`, expected a boolean",
      { "title" => 2 ** 64 } => "invalid type: floating point `1.8446744073709552e19`, expected a string",
      { "multiple" => "a\u200bb\u0085\u0301" } => 'invalid type: string "a\u{200b}b\u{85}\u{301}", expected a boolean',
    }.each do |options, message|
      assert_equal "invalid args `options` for command `open`: #{message}", rejection("open", { "options" => options }), options.inspect
    end
  end

  # serde_json's Map is a BTreeMap without its preserve_order feature, so
  # serde visits an object's keys in byte order, whatever order the
  # frontend sent them in, and names the first bad one in that order
  # (plan 024, Results). The messages are the plan 026 oracle's.
  def test_an_object_is_read_in_key_order
    {
      { "title" => 1, "multiple" => 2 } => "invalid type: integer `2`, expected a boolean",
      { "title" => 1, "defaultPath" => 2 } => "invalid type: integer `2`, expected path string",
      { "filters" => [{ "name" => 1, "extensions" => 2 }] } => "invalid type: integer `2`, expected a sequence",
    }.each do |options, message|
      assert_equal "invalid args `options` for command `open`: #{message}", rejection("open", { "options" => options }), options.inspect
    end
  end

  # serde_derive reads a struct from a sequence too, field by field in
  # declaration order: a missing field takes its serde default if it has
  # one, and otherwise ends the read (de.rs visit_seq). The messages are
  # the plan 026 oracle's.
  def test_options_may_be_a_sequence
    options = Dialog::Commands.__send__(:arguments, { "options" => ["t", [["n", ["txt"]]], true, false, "/p", false, nil, "image"] }, "open").open_options
    assert_equal Dialog::Commands::OpenDialogOptions.new(
      title: "t", filters: [Dialog::Commands::DialogFilter.new(name: "n", extensions: ["txt"])], multiple: true, directory: false,
      default_path: "/p", recursive: false, can_create_directories: nil, picker_mode: Dialog::PickerMode::Image, file_access_mode: nil,
    ), options
    {
      ["open", ["t"]] => "invalid length 4, expected struct OpenDialogOptions with 9 elements",
      ["open", [1]] => "invalid type: integer `1`, expected a string",
      ["open", ["t", [], true, false, "/p", false, nil, "image", "copy", "extra"]] => "invalid length 10, expected fewer elements in array",
      ["save", []] => "invalid length 0, expected struct SaveDialogOptions with 4 elements",
      ["save", ["t"]] => "invalid length 2, expected struct SaveDialogOptions with 4 elements",
      ["save", ["t", [], "/p", true, 1]] => "invalid length 5, expected fewer elements in array",
    }.each do |(command, sequence), message|
      assert_equal "invalid args `options` for command `#{command}`: #{message}", rejection(command, { "options" => sequence }), sequence.inspect
    end
  end

  # serde_json quotes a string as Rust's Debug does (de/mod.rs:410).
  def test_a_string_in_a_message_is_quoted_as_rust_debugs_it
    expected = 'invalid type: string "a\"b\n\u{1}#{x}", expected a boolean'
    assert_equal "invalid args `options` for command `open`: #{expected}",
      rejection("open", { "options" => { "multiple" => "a\"b\n\u0001\#{x}" } })
  end

  def test_each_save_option_checks_its_type
    assert_equal "invalid args `options` for command `save`: invalid type: boolean `false`, expected a string",
      rejection("save", { "options" => { "title" => false } })
    assert_equal "invalid args `options` for command `save`: invalid type: integer `1`, expected path string",
      rejection("save", { "options" => { "defaultPath" => 1 } })
  end

  def test_each_message_argument_checks_its_type
    assert_equal "invalid args `message` for command `message`: invalid type: integer `1`, expected a string",
      rejection("message", { "message" => 1 })
    assert_equal "invalid args `title` for command `ask`: invalid type: boolean `true`, expected a string",
      rejection("ask", { "message" => "m", "title" => true })
    assert_equal "invalid args `kind` for command `confirm`: invalid type: integer `3`, expected a string",
      rejection("confirm", { "message" => "m", "kind" => 3 })
    assert_equal "invalid args `okButtonLabel` for command `message`: invalid type: sequence, expected a string",
      rejection("message", { "message" => "m", "okButtonLabel" => [] })
    assert_equal "invalid args `noButtonLabel` for command `ask`: invalid type: map, expected a string",
      rejection("ask", { "message" => "m", "noButtonLabel" => {} })
  end

  # MessageDialogButtons is an externally tagged enum, read by serde_json
  # (value/de.rs:328-347, 1066-1107).
  def test_buttons_follow_serdes_enum_rules
    {
      "Maybe" => "unknown variant `Maybe`, expected one of `Ok`, `OkCancel`, `YesNo`, `YesNoCancel`, " \
        "`OkCustom`, `OkCancelCustom`, `YesNoCancelCustom`",
      "OkCustom" => "invalid type: unit variant, expected newtype variant",
      "OkCancelCustom" => "invalid type: unit variant, expected tuple variant",
      1 => "invalid type: integer `1`, expected string or map",
      {} => "invalid value: map, expected map with a single key",
      { "Ok" => nil, "YesNo" => nil } => "invalid value: map, expected map with a single key",
      { "Ok" => 1 } => "invalid type: integer `1`, expected unit",
      { "OkCustom" => 1 } => "invalid type: integer `1`, expected a string",
      { "OkCancelCustom" => "Save" } => "invalid type: string \"Save\", expected tuple variant",
      { "OkCancelCustom" => [] } => "invalid type: null, expected tuple variant MessageDialogButtons::OkCancelCustom",
      { "OkCancelCustom" => ["Save"] } =>
        "invalid length 1, expected tuple variant MessageDialogButtons::OkCancelCustom with 2 elements",
      { "OkCancelCustom" => %w[a b c] } => "invalid length 3, expected fewer elements in array",
      { "YesNoCancelCustom" => ["a", 2, "c"] } => "invalid type: integer `2`, expected a string",
      { "Nope" => nil } => "unknown variant `Nope`, expected one of `Ok`, `OkCancel`, `YesNo`, `YesNoCancel`, " \
        "`OkCustom`, `OkCancelCustom`, `YesNoCancelCustom`",
    }.each do |buttons, message|
      assert_equal "invalid args `buttons` for command `message`: #{message}",
        rejection("message", { "message" => "m", "buttons" => buttons }), buttons.inspect
    end
  end

  def test_buttons_read_every_variant
    {
      "Ok" => Dialog::MessageDialogButtons::Ok,
      "YesNoCancel" => Dialog::MessageDialogButtons::YesNoCancel,
      { "OkCancel" => nil } => Dialog::MessageDialogButtons::OkCancel,
      { "OkCustom" => "Fine" } => Dialog::MessageDialogButtons::OkCustom.new(ok: "Fine"),
      { "OkCancelCustom" => %w[Save Discard] } => Dialog::MessageDialogButtons::OkCancelCustom.new(ok: "Save", cancel: "Discard"),
      { "YesNoCancelCustom" => %w[Y N C] } => Dialog::MessageDialogButtons::YesNoCancelCustom.new(yes: "Y", no: "N", cancel: "C"),
    }.each do |wire, expected|
      args = Dialog::Commands.__send__(:arguments, { "buttons" => wire }, "message")
      assert_equal expected, args.buttons("buttons"), wire.inspect
    end
  end

  # Any string, any case; anything unknown is info (models.rs:20-33).
  def test_a_kind_is_any_string
    { "WARNING" => :Warning, "error" => :Error, "loud" => :Info }.each do |wire, kind|
      args = Dialog::Commands.__send__(:arguments, { "kind" => wire }, "message")
      assert_same Dialog::MessageDialogKind.const_get(kind, false), args.kind("kind"), wire
    end
  end

  # ask and confirm pick their buttons from the labels they get
  # (commands.rs:319-366); message from buttons, then okButtonLabel
  # (commands.rs:300-304).
  def test_the_buttons_each_command_shows
    commands = Dialog::Commands
    custom = Dialog::MessageDialogButtons::OkCancelCustom
    assert_same Dialog::MessageDialogButtons::YesNo, commands.ask_buttons(nil, nil)
    assert_equal custom.new(ok: "Sure", cancel: "No"), commands.ask_buttons("Sure", nil)
    assert_equal custom.new(ok: "Yes", cancel: "Nope"), commands.ask_buttons(nil, "Nope")
    assert_same Dialog::MessageDialogButtons::OkCancel, commands.confirm_buttons(nil, nil)
    assert_equal custom.new(ok: "Go", cancel: "Cancel"), commands.confirm_buttons("Go", nil)
    assert_equal custom.new(ok: "Ok", cancel: "Stop"), commands.confirm_buttons(nil, "Stop")
    assert_same Dialog::MessageDialogButtons::Ok, commands.message_buttons(nil, nil)
    assert_equal Dialog::MessageDialogButtons::OkCustom.new(ok: "Fine"), commands.message_buttons(nil, "Fine")
    assert_same Dialog::MessageDialogButtons::YesNo, commands.message_buttons(Dialog::MessageDialogButtons::YesNo, "Fine")
  end
end
