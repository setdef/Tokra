#!/usr/bin/env ruby
# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Converts a Claude Code session transcript (JSONL) into the
# doc/contributors/chats/NNN.md format: user messages and assistant text in
# full, tool calls as one-line summaries, tool results left out.
#
# It only reads the transcript and writes Markdown. It never runs git.

require "json"
require "optparse"

USAGE = <<~TEXT
  Usage: export_transcript.rb [options] [TRANSCRIPT.jsonl]

  Without TRANSCRIPT, reads the current Claude Code session: the file named
  by $CLAUDE_CODE_SESSION_ID in this directory's project folder under
  $CLAUDE_CONFIG_DIR (default ~/.claude), or else the newest transcript there.

  Options:
    --title TITLE        Heading (default "Chat Conversation")
    --next               Write doc/contributors/chats/NNN.md, the next number,
                         and print its path (never overwrites)
    --output PATH        Write PATH instead of stdout (never overwrites)
    --copyright HOLDER   SPDX copyright holder (default: "$GIT_AUTHOR_NAME
                       <$GIT_AUTHOR_EMAIL>"; one of the two is required)

  Exit codes: 0 written, 1 transcript not found, 2 bad arguments or no
  copyright holder, 3 output exists.
TEXT

options = { title: "Chat Conversation" }
begin
  OptionParser.new do |parser|
    parser.banner = USAGE
    parser.on("--title TITLE") { |title| options[:title] = title }
    parser.on("--next") { options[:next] = true }
    parser.on("--output PATH") { |path| options[:output] = path }
    parser.on("--copyright HOLDER") { |holder| options[:copyright] = holder }
  end.parse!
rescue OptionParser::ParseError => e
  warn "Error: #{e.message}\n\n#{USAGE}"
  exit 2
end
if options[:next] && options[:output]
  warn "Error: pass --next or --output, not both."
  exit 2
end

# The transcript of the session running in this directory.
def current_transcript
  config = ENV.fetch("CLAUDE_CONFIG_DIR", File.join(Dir.home, ".claude"))
  project = File.join(config, "projects", File.realpath(Dir.pwd).gsub(/[^A-Za-z0-9]/, "-"))
  session = ENV.fetch("CLAUDE_CODE_SESSION_ID", nil)
  return File.join(project, "#{session}.jsonl") if session

  Dir.glob(File.join(project, "*.jsonl")).max_by { |path| File.mtime(path) } || project
end

# The holder from Git's author variables, read from the environment so the
# script never runs git.
def copyright_holder
  name = ENV.fetch("GIT_AUTHOR_NAME", "").strip
  email = ENV.fetch("GIT_AUTHOR_EMAIL", "").strip
  return if name.empty?

  email.empty? ? name : "#{name} <#{email}>"
end

def tool_line(block)
  input = block["input"] || {}
  case block["name"]
  when "Bash" then "*Ran `#{input['command'].to_s.lines.first.to_s.strip}`*"
  when "Read" then "*Viewed #{input['file_path']}*"
  when "Edit", "Write", "NotebookEdit" then "*Edited #{input['file_path']}*"
  when "Grep" then "*Searched for `#{input['pattern']}`*"
  when "Glob" then "*Listed `#{input['pattern']}`*"
  else "*Used #{block['name']}*"
  end
end

# Tags Claude Code wraps around messages it adds to the user's turn: slash
# commands and their output, reminders, background-task notices, hooks.
HARNESS_TAGS = %w[
  command-name
  command-message
  command-args
  local-command-stdout
  local-command-stderr
  local-command-caveat
  system-reminder
  task-notification
  user-prompt-submit-hook
  bash-input
  bash-stdout
  bash-stderr
].freeze

def harness?(text)
  HARNESS_TAGS.include?(text.lstrip[/\A<([a-z-]+)>/, 1])
end

# What the user typed: string content, or the text blocks of array content.
# Tool results (the other blocks) and harness messages are omitted.
def user_section(content)
  texts = content.is_a?(String) ? [content] : Array(content).filter_map { |block| block["text"] if block["type"] == "text" }
  texts = texts.map(&:strip).reject { |text| text.empty? || harness?(text) }
  return if texts.empty?

  "### User Input\n\n#{texts.join("\n\n")}\n"
end

def assistant_sections(content)
  Array(content).filter_map do |block|
    case block["type"]
    when "text"
      text = block["text"].to_s.strip
      "### Planner Response\n\n#{text}\n" unless text.empty?
    when "tool_use" then "#{tool_line(block)}\n"
    end
  end
end

transcript = ARGV.first || current_transcript
unless File.file?(transcript)
  warn "Error: no transcript at #{transcript}. Pass the session's .jsonl path."
  exit 1
end

year = Time.now.year
holder = options[:copyright] || copyright_holder
unless holder
  warn "Error: pass --copyright \"Name <email>\", or set GIT_AUTHOR_NAME (and GIT_AUTHOR_EMAIL)."
  exit 2
end
# REUSE-IgnoreStart
out = ["<!--\nSPDX-FileCopyrightText: #{year} #{holder}\n\nSPDX-License-Identifier: CC-BY-SA-4.0\n-->\n"]
# REUSE-IgnoreEnd
out << "# #{options[:title]}\n"
out << "Note: _This is the conversational output of a Claude Code session. " \
  "Tool results are omitted; tool calls are summarized._\n"

File.foreach(transcript) do |line|
  entry = JSON.parse(line)
  message = entry["message"] or next
  # A compaction summary is the harness restating the session, not the user.
  next if entry["isCompactSummary"]

  case entry["type"]
  when "user" then out << user_section(message["content"])
  when "assistant" then out.concat(assistant_sections(message["content"]))
  end
end
markdown = out.compact.join("\n")

path = options[:output]
if options[:next]
  chats = File.join("doc", "contributors", "chats")
  number = Dir.glob("[0-9][0-9][0-9].md", base: chats).map(&:to_i).max.to_i + 1
  path = File.join(chats, format("%03d.md", number))
end

if path
  begin
    File.write(path, markdown, mode: "wx")
  rescue Errno::EEXIST
    warn "Error: #{path} exists; choose another --output."
    exit 3
  end
  puts path
else
  print markdown
end
