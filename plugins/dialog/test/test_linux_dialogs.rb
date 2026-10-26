# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/dialog_test"

# Every command end to end on Linux, answered by a stand-in for zenity.
#
# rfd's portal backend asks the XDG desktop portal over D-Bus and, when
# that fails, runs zenity; its message dialogs always run zenity (rfd
# 0.17.2 src/backend/xdg_desktop_portal.rs:98-113, 297-341). With D-Bus
# pointed at a socket that does not exist and a fake zenity first on PATH,
# each command runs the plugin's whole path: the argument checks, the
# worker thread, the main-thread start through RuntimeContext, rfd's
# future awaited on its own thread, and the answer. The fake records the
# arguments rfd gave it and answers as zenity would, the technique
# ferro-rfd's tests use. Each runs in a child process.
class TestLinuxDialogs < Minitest::Test
  include DialogTest

  FAKE_ZENITY = <<~SH
    #!/bin/sh
    printf '%s\\n' "$@" > "$FAKE_ZENITY_LOG"
    printf '%s' "$FAKE_ZENITY_OUTPUT"
    exit "${FAKE_ZENITY_STATUS:-0}"
  SH

  def setup
    skip_unless_platform(:linux)
    @dir = Dir.mktmpdir("tokra-dialog")
    bin = File.join(@dir, "bin")
    Dir.mkdir(bin)
    File.write(File.join(bin, "zenity"), FAKE_ZENITY)
    File.chmod(0o755, File.join(bin, "zenity"))
    @path = "#{bin}:/usr/bin:/bin"
    @log = File.join(@dir, "zenity.log")
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir
  end

  # Runs +command+ with +payload+ in a child whose zenity prints +output+
  # and exits with +status+. Returns the invoke's <tt>[success, value]</tt>
  # and the arguments rfd passed zenity.
  private def run_command(command, payload, output: "", status: 0)
    run_script("#{CHILD_COMMAND}\nrun_command(#{command.dump}, #{payload.inspect})", output:, status:)
  end

  # Runs +script+ in a child whose zenity prints +output+ and exits with
  # +status+. Returns the script's value and the arguments rfd passed
  # zenity.
  private def run_script(script, output: "", status: 0)
    env = {
      "PATH" => @path,
      "DBUS_SESSION_BUS_ADDRESS" => "unix:path=#{File.join(@dir, 'no-bus')}",
      "FAKE_ZENITY_LOG" => @log,
      "FAKE_ZENITY_OUTPUT" => output,
      "FAKE_ZENITY_STATUS" => status.to_s,
    }
    value, = in_child(script, env)
    [value, File.exist?(@log) ? File.read(@log).lines(chomp: true) : nil]
  end

  def test_open_resolves_the_picked_file
    answer, args = run_command("open", {
"options" => {
"filters" => [{ "name" => "Text", "extensions" => ["txt"] }],
"defaultPath" => "/nowhere/notes.txt",
},
},
      output: "/home/me/notes one.txt\n")

    assert_equal [true, "/home/me/notes one.txt"], answer
    assert_equal ["--no-markup", "--file-selection", "--file-filter", "Text | *.txt", "--filename", "notes.txt"], args
  end

  # OpenResponse's variants (commands.rs:153-217).
  def test_open_picks_files_folders_or_one_folder
    assert_equal [true, ["/a", "/b"]], run_command("open", { "options" => { "multiple" => true } }, output: "/a|/b\n").first
    folders, args = run_command("open", { "options" => { "directory" => true, "multiple" => true } }, output: "/a|/b\n")
    assert_equal [true, ["/a", "/b"]], folders
    assert_equal ["--no-markup", "--file-selection", "--directory", "--multiple"], args
    assert_equal [true, "/a"], run_command("open", { "options" => { "directory" => true } }, output: "/a\n").first
  end

  # zenity exits 1 when the user cancels: null for one path, and rfd's
  # empty list for several (zenity.rs:95-109).
  def test_a_cancelled_open_resolves_null_or_an_empty_list
    assert_equal [true, nil], run_command("open", { "options" => {} }, status: 1).first
    assert_equal [true, []], run_command("open", { "options" => { "multiple" => true } }, status: 1).first
  end

  def test_save_resolves_the_chosen_path
    answer, args = run_command("save", { "options" => { "defaultPath" => "/nowhere/out.csv" } }, output: "/home/me/out.csv\n")

    assert_equal [true, "/home/me/out.csv"], answer
    assert_equal ["--no-markup", "--file-selection", "--save", "--confirm-overwrite", "--filename", "out.csv"], args
  end

  def test_message_resolves_the_button_pressed
    answer, args = run_command("message", { "message" => "Disk almost full", "title" => "Careful", "kind" => "warning" })

    assert_equal [true, "Ok"], answer
    assert_equal ["--no-markup", "--warning", "--title", "Careful", "--text", "Disk almost full"], args
  end

  # The command answers with the custom label even where rfd answers Ok
  # (desktop.rs:227-253).
  def test_message_with_custom_buttons_resolves_a_label
    answer, args = run_command("message", { "message" => "Keep?", "buttons" => { "OkCancelCustom" => %w[Keep Drop] } },
      status: 1)

    assert_equal [true, "Drop"], answer
    assert_equal [
      "--no-markup",
      "--question",
      "--title",
      "",
      "--text",
      "Keep?",
      "--ok-label",
      "Keep",
      "--cancel-label",
      "Drop",
], args
    assert_equal [true, "Fine"], run_command("message", { "message" => "m", "okButtonLabel" => "Fine" }).first
  end

  def test_ask_and_confirm_resolve_true_or_false
    assert_equal [true, true], run_command("ask", { "message" => "Sure?" }).first
    assert_equal [true, false], run_command("ask", { "message" => "Sure?" }, status: 1).first
    answer, args = run_command("confirm", { "message" => "Go?", "okButtonLabel" => "Go" })
    assert_equal [true, true], answer
    assert_equal [
      "--no-markup",
      "--question",
      "--title",
      "",
      "--text",
      "Go?",
      "--ok-label",
      "Go",
      "--cancel-label",
      "Cancel",
], args
    assert_equal [true, false], run_command("confirm", { "message" => "Go?" }, status: 1).first
  end

  # The Ruby API's block forms, called on the main thread as an app's
  # setup hook or event handler would: each returns at once and answers
  # on another thread (lib.rs:319-348, 510-654).
  CALLBACKS = <<~RUBY
    app = Tokra::Builder.default.build(native: StubNative)
    handle = app.handle
    handle.plugin(Tokra::Plugins::Dialog::Plugin.new(handle))
    buttons = Tokra::Plugins::Dialog::MessageDialogButtons::OkCancelCustom.new(ok: "Keep", cancel: "Drop")
    answers = Thread::Queue.new
  RUBY

  def test_show_yields_whether_the_ok_label_was_pressed
    script = "#{CALLBACKS}\nhandle.dialog.message('Keep?').buttons(buttons).show { |ok| answers << ok }\nanswers.pop"
    assert_equal true, run_script(script).first
    assert_equal false, run_script(script, status: 1).first
  end

  def test_show_with_result_yields_the_label_pressed
    script = "#{CALLBACKS}\nhandle.dialog.message('Keep?').buttons(buttons)" \
      ".show_with_result { |result| answers << result.to_s }\nanswers.pop"
    assert_equal "Drop", run_script(script, status: 1).first
  end

  def test_the_file_block_forms_yield_paths
    {
      "pick_file" => ["/a\n", "/a"],
      "pick_files" => ["/a|/b\n", ["/a", "/b"]],
      "pick_folder" => ["/d\n", "/d"],
      "pick_folders" => ["/d|/e\n", ["/d", "/e"]],
      "save_file" => ["/s.txt\n", "/s.txt"],
    }.each do |call, (output, expected)|
      script = "#{CALLBACKS}\nreturned = handle.dialog.file.#{call} { |path| answers << path }\n[returned, answers.pop]"
      assert_equal [nil, expected], run_script(script, output:).first, call
    end
  end
end
