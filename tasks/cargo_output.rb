# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "open3"

# Runs a build command and fails on any warning rustc, Clippy, or Cargo
# prints.
#
# The gate allows no warnings, but most build steps exit zero with them:
# cargo build and cargo test print rustc warnings and succeed, and even
# <tt>clippy -D warnings</tt> lets some through. An unknown lint in a
# crate's [lints] table reaches rustc as a command-line flag, and the
# unknown_lints lint ignores -D warnings, so a misspelled lint name printed
# <tt>warning[E0602]</tt> while the gate passed. This runner reads the output
# instead of trusting the exit status.
#
# Cargo replays a crate's warnings on a cached build, so a warning cannot
# hide behind a build that was already up to date.
class CargoOutput
  # A line that starts a rustc, Clippy, or Cargo warning: <tt>warning: ...</tt>
  # or <tt>warning[E0602]: ...</tt>, at the start of the line.
  WARNING = /^warning(?:\[[A-Za-z0-9_]+\])?: /

  # A terminal color or style sequence. Cargo and rustc color their output
  # when CARGO_TERM_COLOR is +always+, as dtolnay/rust-toolchain sets it in
  # CI, and a colored warning starts with one of these instead of
  # <tt>warning</tt>.
  STYLE = /\e\[[0-9;]*m/

  # Raised when the command fails or warns; the message lists the warnings.
  class Failure < StandardError; end

  # The warning lines in +output+.
  def self.warnings(output)
    output.lines.map { |line| line.gsub(STYLE, "") }.grep(WARNING).map(&:chomp)
  end

  # Runs +command+ in +chdir+, echoing its output to +out+, and raises
  # Failure if it exits non-zero or prints a warning. Returns the output.
  def self.run!(*command, chdir: Dir.pwd, out: $stdout, env: {})
    out.puts "(cd #{chdir} && #{command.join(' ')})"
    output, status = Open3.capture2e(env, *command, chdir:)
    out.print output
    raise Failure, "#{command.join(' ')} failed in #{chdir}" unless status.success?

    found = warnings(output)
    raise Failure, "#{command.join(' ')} warned:\n#{found.map { |line| "  #{line}" }.join("\n")}" if found.any?

    output
  end
end
