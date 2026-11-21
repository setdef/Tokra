# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "open3"
require "tmpdir"

# The packaging check's smoke scripts (tasks/package.rake) run in every
# gate, in whatever session runs it, the maintainer's own included, so
# none may change what that session holds: its clipboard, its hotkeys, or
# its notifications.
class TestPackageSmokes < Minitest::Test
  PACKAGE_RAKE = File.expand_path("../../tasks/package.rake", __dir__)

  # The calls that read or change the session's clipboard, take its
  # hotkeys, or post to its notification center. A read is out too: macOS
  # may ask the person whether this process may paste. A schedule is a
  # call, so NotificationData#schedule, an attribute, is not one.
  SESSION_CALLS = /\.((?:write_text|write_image|write_html|read_text|read_image|clear|set_text|set_html|set_image|
    get_text|get_image|register|register_multiple|show|set_application)\b|schedule(?:_raw)?\()/x

  def test_no_smoke_script_touches_the_session
    source = File.read(PACKAGE_RAKE)

    assert_includes source, "Tokra::Plugins::Clipboard::Clipboard.new", "the clipboard smoke still opens arboard's clipboard"
    assert_empty source.scan(SESSION_CALLS).map(&:first), "a smoke script touches the session"
  end

  # Each smoke script reaches its process as a ruby -e argument, and on
  # Windows the command line Ruby builds for it does not keep a backslash
  # before a quote or a line break, so the script arrives cut short.
  #
  # Ruby requires a command line's -r libraries before RUBYOPT's, so each
  # child names bundler/setup first: otherwise rake loads the Ruby's own
  # default gems, and Bundler refuses where they differ from Gemfile.lock's,
  # as Ruby 4.1's fileutils does (Plan 069).
  def test_no_smoke_script_holds_a_backslash
    smokes, status = Open3.capture2(RbConfig.ruby, "-rbundler/setup", "-rrake", "-rjson", "-e", <<~RUBY, PACKAGE_RAKE)
      load ARGV.fetch(0)
      print JSON.generate(PACKAGES.to_h { |gem| [gem.name, gem.smoke] })
    RUBY

    assert_predicate status, :success?
    JSON.parse(smokes).each { |name, smoke| refute_includes smoke, "\\", name }
  end

  # arboard's error when there is no clipboard to open (common.rs).
  NOT_SUPPORTED = "The selected clipboard is not supported with the current system configuration."

  UNBUNDLED = %w[BUNDLE_GEMFILE BUNDLE_BIN_PATH BUNDLER_SETUP BUNDLER_VERSION RUBYOPT RUBYLIB].to_h { |name| [name, nil] }.freeze

  # Stand-ins for the plugin and ferro-arboard: the clipboard records
  # ARBOARD_ERROR as the plugin records arboard's, or opens.
  CLIPBOARD_LIB = {
    "tokra-clipboard.rb" => <<~RUBY,
      module Ferro
        module Arboard
          class Clipboard
            private def native_set_text; end
          end
        end
      end

      module Tokra
        module Plugins
          module Clipboard
            class Clipboard
              def initialize
                @error = ENV["ARBOARD_ERROR"]
                @clipboard = Ferro::Arboard::Clipboard.new unless @error
              end
            end
          end
        end
      end
    RUBY
    "tokra/plugins/clipboard/version.rb" => %(module Tokra::Plugins::Clipboard; VERSION = "9.9.9"; end\n),
  }.freeze

  # Runs tokra-clipboard's smoke script against the stand-ins, with a
  # launchctl that answers +session+, or none, on PATH. Returns what it
  # printed and its status.
  private def clipboard_smoke(error: nil, session: nil)
    smoke, status = Open3.capture2(RbConfig.ruby, "-rbundler/setup", "-rrake", "-e", <<~RUBY, PACKAGE_RAKE)
      load ARGV.fetch(0)
      print PACKAGES.find { |gem| gem.name == "tokra-clipboard" }.smoke
    RUBY
    assert_predicate status, :success?

    Dir.mktmpdir("smoke") do |dir|
      CLIPBOARD_LIB.each do |path, source|
        FileUtils.mkdir_p(File.dirname(File.join(dir, "lib", path)))
        File.write(File.join(dir, "lib", path), source)
      end
      Dir.mkdir(File.join(dir, "bin"))
      if session
        File.write(File.join(dir, "bin/launchctl"), "#!/bin/sh\n[ \"$1\" = managername ] && echo #{session}\n")
        File.chmod(0o755, File.join(dir, "bin/launchctl"))
      end
      # The script runs outside the bundle, as the packaging check runs it.
      env = UNBUNDLED.merge("PATH" => File.join(dir, "bin"), "ARBOARD_ERROR" => error)
      Open3.capture2e(env, RbConfig.ruby, "-I", File.join(dir, "lib"), "-e", smoke, dir)
    end
  end

  def test_the_clipboard_smoke_opens_the_clipboard_where_there_is_one
    skip "Ruby on Windows cannot run the stand-in launchctl" if Gem.win_platform?

    output, status = clipboard_smoke(session: "Aqua")

    assert_predicate status, :success?, output
    assert_equal "tokra-clipboard 9.9.9 opens the clipboard through ferro-arboard\n", output
  end

  # A Mac with no GUI session has no pasteboard, and arboard says so; the
  # plugin still reached ferro-arboard's extension to hear it.
  def test_on_a_mac_with_no_gui_session_the_clipboard_smoke_takes_arboard_s_answer_and_says_why
    skip "Ruby on Windows cannot run the stand-in launchctl" if Gem.win_platform?

    output, status = clipboard_smoke(error: NOT_SUPPORTED, session: "System")

    assert_predicate status, :success?, output
    assert_equal "tokra-clipboard 9.9.9 reaches ferro-arboard, which opens no clipboard here: " \
      "no macOS GUI session (launchctl managername is \"System\", not \"Aqua\")\n", output
  end

  # Where there is a session, or no launchd at all, or arboard fails some
  # other way, a clipboard that does not open fails the check.
  def test_elsewhere_a_clipboard_that_does_not_open_fails_the_smoke
    skip "Ruby on Windows cannot run the stand-in launchctl" if Gem.win_platform?

    [
      [NOT_SUPPORTED, "Aqua"],
      [NOT_SUPPORTED, nil],
      ["Unknown error while interacting with the clipboard: no", "System"],
    ].each do |error, session|
      output, status = clipboard_smoke(error:, session:)

      refute_predicate status, :success?, [error, session].inspect
      assert_includes output, "arboard could not open the clipboard: #{error}"
    end
  end
end
