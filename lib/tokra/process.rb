# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "rbconfig"

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: process module adapted from tauri/crates/tauri/src/process.rs and
# tauri/crates/tauri-utils/src/platform/starting_binary.rs

module Tokra
  # Starts your app over.
  #
  # AppHandle#restart and AppHandle#request_restart end with Process.restart,
  # and you can call it yourself where no app handle reaches. Inside
  # <tt>module Tokra</tt>, a bare +Process+ names this module; write
  # <tt>::Process</tt> for Ruby's.
  #
  # Mirrors Tauri's <tt>tauri::process</tt> module (process.rs).
  module Process
    # The binary the process started from, found as safely as Tokra can:
    # canonical, and on macOS refused when a symlink leads to it, since
    # macOS protects symlinks less than other systems.
    #
    # Mirrors Tauri's <tt>StartingBinary</tt>
    # (tauri-utils platform/starting_binary.rs:11-80).
    class StartingBinary
      # Finds the binary at +dangerous_path+ and keeps the canonical path,
      # or the reason it cannot be used.
      def initialize(dangerous_path)
        symlink = symlink_in(dangerous_path)
        if symlink
          @error = "StartingBinary found current_exe() that contains a symlink on a non-allowed platform: " \
            "#{symlink}"
        end
        @path = File.realpath(dangerous_path).freeze unless @error
      rescue SystemCallError => e
        @error = e.message
      end

      # The canonical path. Raises Error::Io when the binary cannot be used.
      #
      # === Example
      #
      #   Tokra::Process::StartingBinary.new(RbConfig.ruby).cloned
      def cloned
        raise Error::Io, @error if @error

        @path
      end

      # The first of +path+ and its ancestors that is a symlink, on macOS
      # only; +nil+ elsewhere, as with Tauri's
      # <tt>process-relaunch-dangerous-allow-symlink-macos</tt> feature off
      # (Plan 039, decision 6).
      private def symlink_in(path)
        return nil unless RbConfig::CONFIG["host_os"].include?("darwin")

        Pathname.new(path).ascend.find(&:symlink?)&.to_s
      end
    end

    # The Ruby interpreter running your app, cached when Tokra loads.
    STARTING_BINARY = StartingBinary.new(RbConfig.ruby)

    # The path of the binary the app runs on: for a Ruby app, the Ruby
    # interpreter, canonical. The script it runs is the first argument
    # after it in Env#args_os.
    #
    # The interpreter is RbConfig.ruby, the one this Ruby was built as,
    # which can differ from the executable running now: an app started
    # with <tt>rubyw.exe</tt> on Windows restarts under
    # <tt>ruby.exe</tt>, which opens a console window. Tauri reads the
    # running executable; Tokra does not yet, because on macOS that path
    # often runs through a symlink, such as Homebrew's
    # <tt>opt/ruby</tt>, which the symlink refusal would reject
    # (Plan 039, decision 1).
    #
    # Raises Error::Io when the interpreter cannot be found, or on macOS
    # when a symlink leads to it.
    #
    # Mirrors Tauri's <tt>process::current_binary</tt> (process.rs:11-56)
    # and <tt>tauri_utils::platform::current_exe</tt> (platform.rs:172-174).
    #
    # === Example
    #
    #   Tokra::Process.current_binary(handle.env) # => "/usr/local/bin/ruby"
    def self.current_binary(_env)
      STARTING_BINARY.cloned
    end

    # Starts the app again and ends this process with status 0.
    #
    # Runs current_binary with every argument in +env+ after the first: the
    # same script, with the same arguments, in the working directory and
    # environment this process has now. The new process starts before this
    # one ends, and shares its standard streams. If it cannot start, the
    # failure goes to <tt>$stderr</tt>, and this process still exits. An
    # app with no script file, run with <tt>ruby -e</tt> or from standard
    # input, has nothing to run again: the restart refuses with an
    # Error::Io, reported the same way, rather than run an argument as
    # code or wait on standard input.
    #
    # Ends with Kernel.exit, so +ensure+ clauses and +at_exit+ hooks run.
    #
    # Mirrors Tauri's <tt>process::restart</tt> (process.rs:58-87).
    # Packaged apps, which Tauri restarts through their bundle's executable
    # (process.rs:89-133), wait for a packager (Plan 039, Out of scope).
    #
    # === Example
    #
    #   Tokra::Process.restart(handle.env)
    def self.restart(env)
      begin
        path = current_binary(env)
      rescue Error::Io
        path = nil
      end
      if path
        begin
          script = env.args_os[1]
          raise Error::Io, "the app's script is not a file: #{script.inspect}" unless script && File.file?(script)

          # The two-element first argument runs the binary without a shell,
          # as Rust's Command does, whatever the arguments hold.
          # RBS declares only spawn's String form.
          ::Process.spawn([path, path], *env.args_os.drop(1)) # steep:ignore NoMethod
        rescue Error::Io, SystemCallError => e
          warn("failed to restart app: #{e.message}")
        end
      end
      Kernel.exit(0)
    end
  end
end

# SPDX-SnippetEnd
