# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "json"
require "open3"
require "tmpdir"

# Tests the commit-session skill's transcript exporter by running it on a
# small Claude Code transcript, the way an agent does.
class TestExportTranscript < Minitest::Test
  SCRIPT = File.expand_path("../../.agents/skills/commit-session/scripts/export_transcript.rb", __dir__)
  HOLDER = "Ada Lovelace <ada@example.com>"

  ENTRIES = [
    { type: "user", message: { content: "Port the clipboard plugin." } },
    { type: "user", message: { content: "<command-name>/clear</command-name>" } },
    { type: "user", message: { content: "<system-reminder>be brief</system-reminder>" } },
    { type: "user", isCompactSummary: true, message: { content: "This session is being continued." } },
    {
type: "assistant",
message: {
content: [
  { type: "text", text: "Reading the source first." },
  { type: "tool_use", name: "Bash", input: { command: "ls vendor\nmore" } },
  { type: "tool_use", name: "Read", input: { file_path: "lib/tokra.rb" } },
  { type: "tool_use", name: "Edit", input: { file_path: "lib/tokra/app.rb" } },
  { type: "tool_use", name: "WebFetch", input: { url: "https://example.com" } },
    ],
},
},
    { type: "user", message: { content: [{ type: "tool_result", content: "secret output" }] } },
    {
type: "user",
message: {
content: [
  { type: "text", text: "<b>Bold</b> ideas, typed with an image." },
  { type: "image", source: {} },
],
},
},
    { type: "system", message: { content: "ignored" } },
  ].freeze

  def setup
    @dir = Dir.mktmpdir("export_transcript")
    @transcript = File.join(@dir, "session.jsonl")
    File.write(@transcript, ENTRIES.map { |entry| JSON.generate(entry) }.join("\n") << "\n")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  # Bundler stays out: the script is standalone, and loading the bundle
  # would run git for the gemspec.
  UNBUNDLED = %w[RUBYOPT RUBYLIB BUNDLE_GEMFILE BUNDLE_BIN_PATH BUNDLER_SETUP].to_h { |name| [name, nil] }.freeze

  private def run_script(*, env: {})
    Open3.capture3(UNBUNDLED.merge(env), RbConfig.ruby, SCRIPT, *, chdir: @dir)
  end

  private def export(*, env: {})
    run_script("--copyright", HOLDER, *, env:)
  end

  def test_formats_a_transcript_like_the_committed_chats
    out, err, status = export(@transcript)

    assert status.success?, err
    # REUSE-IgnoreStart
    assert_equal <<~MARKDOWN, out
      <!--
      SPDX-FileCopyrightText: #{Time.now.year} #{HOLDER}

      SPDX-License-Identifier: CC-BY-SA-4.0
      -->

      # Chat Conversation

      Note: _This is the conversational output of a Claude Code session. Tool results are omitted; tool calls are summarized._

      ### User Input

      Port the clipboard plugin.

      ### Planner Response

      Reading the source first.

      *Ran `ls vendor`*

      *Viewed lib/tokra.rb*

      *Edited lib/tokra/app.rb*

      *Used WebFetch*

      ### User Input

      <b>Bold</b> ideas, typed with an image.
    MARKDOWN
    # REUSE-IgnoreEnd
    refute_includes out, "secret output"
    refute_includes out, "being continued"
  end

  def test_takes_a_title
    out, = export("--title", "Porting the clipboard", @transcript)

    assert_includes out, "\n# Porting the clipboard\n"
  end

  # With no --copyright, the holder comes from Git's author variables, and
  # git itself is never run: PATH holds only Ruby's directory.
  def test_reads_the_holder_from_the_environment_without_git
    env = {
"PATH" => File.dirname(RbConfig.ruby),
"GIT_AUTHOR_NAME" => "Grace Hopper",
"GIT_AUTHOR_EMAIL" => "grace@example.com",
}

    out, err, status = run_script(@transcript, env:)

    assert status.success?, err
    assert_includes out, "SPDX-FileCopyrightText: #{Time.now.year} Grace Hopper <grace@example.com>"
  end

  def test_without_a_holder_it_explains_and_exits_2
    _, err, status = run_script(@transcript, env: { "PATH" => File.dirname(RbConfig.ruby), "GIT_AUTHOR_NAME" => nil })

    assert_equal 2, status.exitstatus
    assert_includes err, "pass --copyright"
  end

  def test_next_writes_the_next_numbered_chat
    chats = File.join(@dir, "doc/contributors/chats")
    FileUtils.mkdir_p(chats)
    File.write(File.join(chats, "007.md"), "old\n")

    out, err, status = export("--next", @transcript)

    assert status.success?, err
    assert_equal "doc/contributors/chats/008.md\n", out
    assert_includes File.read(File.join(chats, "008.md")), "Port the clipboard plugin."
    assert_equal "old\n", File.read(File.join(chats, "007.md"))
  end

  def test_output_refuses_to_overwrite
    existing = File.join(@dir, "existing.md")
    File.write(existing, "keep me\n")

    _, err, status = export("--output", existing, @transcript)

    assert_equal 3, status.exitstatus
    assert_includes err, "exists"
    assert_equal "keep me\n", File.read(existing)
  end

  def test_finds_the_named_session_over_a_newer_one
    project = File.join(@dir, "config", "projects", File.realpath(@dir).gsub(/[^A-Za-z0-9]/, "-"))
    FileUtils.mkdir_p(project)
    FileUtils.cp(@transcript, File.join(project, "abc-123.jsonl"))
    newer = File.join(project, "zzz-999.jsonl")
    File.write(newer, "#{JSON.generate(type: 'user', message: { content: 'Another session.' })}\n")
    File.utime(Time.now + 60, Time.now + 60, newer)
    config = { "CLAUDE_CONFIG_DIR" => File.join(@dir, "config") }

    named, = export(env: config.merge("CLAUDE_CODE_SESSION_ID" => "abc-123"))
    newest, = export(env: config.merge("CLAUDE_CODE_SESSION_ID" => nil))

    assert_includes named, "Port the clipboard plugin."
    assert_includes newest, "Another session."
  end

  def test_explains_a_missing_transcript
    _, err, status = export(File.join(@dir, "nope.jsonl"))

    assert_equal 1, status.exitstatus
    assert_includes err, "no transcript at"
  end
end
