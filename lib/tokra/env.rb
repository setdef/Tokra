# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "rbconfig"

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Env adapted from tauri/crates/tauri-utils/src/lib.rs

module Tokra
  # The command line your app started with.
  #
  # An app that restarts itself, after an update or a settings change that
  # only takes effect on launch, runs the same command again. By then your
  # code may have parsed ARGV away with <tt>OptionParser#parse!</tt> or
  # renamed <tt>$PROGRAM_NAME</tt>. Env keeps the command line as it was
  # when Tokra loaded, and Process.restart runs it again. Every app manages
  # one; read it with Manager#env.
  #
  # #args_os is the interpreter, then the script as an absolute path, then
  # the script's arguments as given. Interpreter options such as
  # <tt>-Ilib</tt> are missing, since Ruby keeps no record of them; options
  # in the +RUBYOPT+ environment variable, such as Bundler's, reach the
  # restarted app through its environment.
  #
  # Mirrors Tauri's <tt>Env</tt> (tauri-utils lib.rs:262-316), whose
  # <tt>args_os</tt> is <tt>std::env::args_os()</tt>. Tauri's Linux fields
  # for AppImages wait for a packager (Plan 039, Out of scope).
  #
  # === Example
  #
  #   handle.env.args_os # => ["/usr/bin/ruby", "/home/me/app/main.rb", "--debug"]
  class Env < Data.define(:args_os)
    # The command line as Ruby saw it when this file loaded: Rust's
    # <tt>args_os</tt> cannot change, and Ruby's ARGV can, so Tokra takes
    # its copy before your code runs, as Tauri caches its starting binary
    # before +main+ (Plan 039, decision 2).
    STARTING_ARGS = [
      RbConfig.ruby,
      File.file?($PROGRAM_NAME) ? File.expand_path($PROGRAM_NAME) : $PROGRAM_NAME,
      *ARGV,
    ].map { |arg| arg.dup.freeze }.freeze

    # The Env of the running process.
    #
    # Mirrors Tauri's <tt>Env::default</tt> (tauri-utils lib.rs:278-316).
    #
    # === Example
    #
    #   Tokra::Env.default.args_os.drop(1) # => the script and its arguments
    def self.default
      new(args_os: STARTING_ARGS)
    end
  end
end

# SPDX-SnippetEnd
