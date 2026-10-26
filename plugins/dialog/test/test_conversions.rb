# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/dialog_test"

# The conversions Tauri's desktop.rs makes between its builders and rfd's,
# and its mapping of rfd's results. Each runs against ferro-rfd's real
# values, and the dialogs are read back through rfd's own Debug text.
class TestConversions < Minitest::Test
  include DialogTest

  Buttons = Dialog::MessageDialogButtons
  Result = Dialog::MessageDialogResult
  Kind = Dialog::MessageDialogKind
  Rfd = Ferro::Rfd

  private def dialog
    @dialog ||= new_dialog
  end

  # desktop.rs:41-49.
  def test_each_kind_becomes_rfds_level
    assert_same Rfd::MessageLevel::Info, Kind::Info.to_message_level
    assert_same Rfd::MessageLevel::Warning, Kind::Warning.to_message_level
    assert_same Rfd::MessageLevel::Error, Kind::Error.to_message_level
  end

  # desktop.rs:110-124.
  def test_each_set_of_buttons_becomes_rfds
    assert_same Rfd::MessageButtons::Ok, Buttons::Ok.to_message_buttons
    assert_same Rfd::MessageButtons::OkCancel, Buttons::OkCancel.to_message_buttons
    assert_same Rfd::MessageButtons::YesNo, Buttons::YesNo.to_message_buttons
    assert_same Rfd::MessageButtons::YesNoCancel, Buttons::YesNoCancel.to_message_buttons
    assert_equal Rfd::MessageButtons::OkCustom.new("Got it"), Buttons::OkCustom.new(ok: "Got it").to_message_buttons
    assert_equal Rfd::MessageButtons::OkCancelCustom.new("Save", "Discard"),
      Buttons::OkCancelCustom.new(ok: "Save", cancel: "Discard").to_message_buttons
    assert_equal Rfd::MessageButtons::YesNoCancelCustom.new("Y", "N", "C"),
      Buttons::YesNoCancelCustom.new(yes: "Y", no: "N", cancel: "C").to_message_buttons
  end

  # models.rs:81-92.
  def test_each_rfd_result_becomes_tauris
    assert_same Result::Yes, Result.from_rfd(Rfd::MessageDialogResult::Yes)
    assert_same Result::No, Result.from_rfd(Rfd::MessageDialogResult::No)
    assert_same Result::Ok, Result.from_rfd(Rfd::MessageDialogResult::Ok)
    assert_same Result::Cancel, Result.from_rfd(Rfd::MessageDialogResult::Cancel)
    assert_equal Result::Custom.new(label: "Save"), Result.from_rfd(Rfd::MessageDialogResult::Custom.new("Save"))
  end

  # models.rs:94-104.
  def test_a_label_becomes_a_result
    assert_same Result::Yes, Result.from("Yes")
    assert_same Result::Cancel, Result.from("Cancel")
    assert_equal Result::Custom.new(label: "yes"), Result.from("yes")
  end

  # rfd on Linux answers standard results for custom labels, so Tauri maps
  # them back to the labels (desktop.rs:227-253); other results pass.
  def test_a_standard_result_for_custom_buttons_becomes_the_label
    ok = Rfd::MessageDialogResult::Ok
    cancel = Rfd::MessageDialogResult::Cancel
    yes = Rfd::MessageDialogResult::Yes
    no = Rfd::MessageDialogResult::No
    ok_custom = Buttons::OkCustom.new(ok: "Fine")
    ok_cancel = Buttons::OkCancelCustom.new(ok: "Save", cancel: "Discard")
    three = Buttons::YesNoCancelCustom.new(yes: "Y", no: "N", cancel: "C")
    {
      [ok, ok_custom] => Result::Custom.new(label: "Fine"),
      [ok, ok_cancel] => Result::Custom.new(label: "Save"),
      [cancel, ok_cancel] => Result::Custom.new(label: "Discard"),
      [yes, three] => Result::Custom.new(label: "Y"),
      [no, three] => Result::Custom.new(label: "N"),
      [cancel, three] => Result::Custom.new(label: "C"),
      [cancel, ok_custom] => Result::Cancel,
      [yes, ok_cancel] => Result::Yes,
      [ok, Buttons::OkCancel] => Result::Ok,
      [Rfd::MessageDialogResult::Custom.new("Save"), ok_cancel] => Result::Custom.new(label: "Save"),
    }.each do |(result, buttons), expected|
      assert_equal expected, Dialog::Desktop.message_dialog_result(result, buttons), [result, buttons].inspect
    end
  end

  # show's boolean: Ok and Yes are true, a custom label is true when it is
  # the OK label, or "Ok" when there is none (lib.rs:322-341).
  def test_show_is_true_for_ok_yes_and_the_ok_label
    ok_cancel = Buttons::OkCancelCustom.new(ok: "Save", cancel: "Discard")
    three = Buttons::YesNoCancelCustom.new(yes: "Y", no: "N", cancel: "C")
    {
      [Result::Ok, Buttons::Ok] => true,
      [Result::Yes, Buttons::YesNo] => true,
      [Result::No, Buttons::YesNo] => false,
      [Result::Cancel, Buttons::OkCancel] => false,
      [Result::Custom.new(label: "Save"), ok_cancel] => true,
      [Result::Custom.new(label: "Discard"), ok_cancel] => false,
      [Result::Custom.new(label: "Y"), three] => true,
      [Result::Custom.new(label: "N"), three] => false,
      [Result::Custom.new(label: "Ok"), Buttons::YesNo] => true,
      [Result::Custom.new(label: "Fine"), Buttons::OkCustom.new(ok: "Fine")] => true,
      [Result::Custom.new(label: "Ok"), Buttons::OkCustom.new(ok: "Fine")] => false,
    }.each do |(result, buttons), expected|
      assert_equal expected, Dialog::MessageDialogBuilder.__send__(:success?, result, buttons), [result, buttons].inspect
    end
  end

  def test_a_message_dialog_carries_title_text_kind_and_buttons_to_rfd
    builder = dialog.message("Disk almost full").title("Careful").kind(Kind::Warning)
      .buttons(Buttons::OkCancelCustom.new(ok: "Clean up", cancel: "Later"))
    debug = builder.to_async_message_dialog.inspect

    assert_includes debug, 'title: "Careful"'
    assert_includes debug, 'description: "Disk almost full"'
    assert_includes debug, "level: Warning"
    assert_includes debug, 'buttons: OkCancelCustom("Clean up", "Later")'
    assert_includes debug, "parent: None"
  end

  # Tauri titles a message dialog with the package name (lib.rs:170-176);
  # Tokra's Config has a product name, unset unless configured.
  def test_a_message_dialog_is_titled_with_the_product_name_or_nothing
    builder = dialog.message("Hi")
    assert_equal "", builder.to_async_message_dialog.inspect[/title: "([^"]*)"/, 1]
    assert_same Kind::Info, builder.instance_variable_get(:@kind)
    assert_same Buttons::Ok, builder.instance_variable_get(:@buttons)
  end

  def test_a_file_dialog_carries_every_option_to_rfd
    builder = dialog.file.set_title("Pick one").set_directory("/tmp").set_file_name("notes.txt")
      .add_filter("Text", ["txt", "md"]).add_filter("All", ["*"]).set_can_create_directories(false)
    debug = builder.to_async_file_dialog.inspect

    assert_includes debug, 'title: Some("Pick one")'
    assert_includes debug, 'starting_directory: Some("/tmp")'
    assert_includes debug, 'file_name: Some("notes.txt")'
    assert_includes debug, 'Filter { name: "Text", extensions: ["txt", "md"] }, Filter { name: "All", extensions: ["*"] }'
    assert_includes debug, "can_create_directories: Some(false)"
  end

  # Tauri always sets it, defaulting to true (desktop.rs:104).
  def test_a_file_dialog_may_create_directories_unless_told_otherwise
    debug = dialog.file.to_async_file_dialog.inspect
    assert_includes debug, "can_create_directories: Some(true)"
    assert_includes debug, "title: None"
    assert_includes debug, "filters: []"
  end

  # Tauri keeps a parent only when it has both handles (lib.rs:287-302).
  def test_a_parent_is_kept_only_with_both_handles
    parent = Data.define(:window_handle, :display_handle)
    window = Rfd::XlibWindowHandle.new(window: 42, visual_id: 0)
    display = Rfd::XlibDisplayHandle.new(display: nil, screen: 0)

    half = dialog.file.set_parent(parent.new(window, nil))
    assert_includes half.to_async_file_dialog.inspect, "parent: None"
    assert_nil dialog.message("x").parent(parent.new(nil, display)).instance_variable_get(:@parent)

    whole = dialog.file.set_parent(parent.new(window, display))
    kept = whole.instance_variable_get(:@parent)
    assert_equal [window, display], [kept.window_handle, kept.display_handle]
  end
end
