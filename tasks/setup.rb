# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "open3"
require "shellwords"

# Tokra's development tools, from the pins in mise.toml, and its git hooks
# (Plans 061 and 073). It is what bin/setup and bin/setup.cmd run, as
#
#   mise trust -q mise.toml
#   mise x -- ruby tasks/setup.rb [--gate]
#
# on every system, so Ruby, Rust, and Python are installed, from nothing,
# before it starts. It runs before the bundle exists, so it needs what
# Ruby ships and no gem. It asks nothing and never runs sudo. On Linux,
# the packages CI installs (.github/workflows/ci.yml, "Install GTK,
# WebKitGTK, and a display server") come from bin/linux-env where Debian
# or Ubuntu lacks them (Plan 068); on another system, install them first.
#
# Every step does nothing when it is already satisfied, so it is quick and
# safe to run again, and it prints a command only when the command does
# something, showing what it printed only if it changed something or
# failed. A command that fails ends it there, with that command's
# status, after the command and what it printed.
#
# With --gate it installs only what the gate needs, and leaves the git
# hooks and the RDoc alone. .githooks/pre-push runs it so before every
# push, so a fresh checkout needs nothing run first.
#
# A CI runner (CI=true) installs the bundle as ci.yml does, and runs
# nothing for a person's commits.
#
# === Example
#
#   Setup.new(root: Dir.pwd, env: ENV.to_h).call("--gate") # => 0
class Setup
  # What a command printed, stdout and stderr together, and its exit status.
  class Result < Data.define(:output, :status)
    def success?
      status.zero?
    end
  end

  # Runs commands for real, from an argument list, never a shell string. A
  # command that cannot start has the status 127, as a shell gives it.
  class Shell
    def initialize(env:)
      @env = env
    end

    # Runs +argv+ in +chdir+, with +env+ added to the environment, and
    # returns its Result.
    def capture(*argv, chdir:, env: {})
      output, status = Open3.capture2e(@env.merge(env), [argv.first, argv.first], *argv.drop(1), chdir:)
      Result.new(output:, status: status.exitstatus || 1)
    rescue SystemCallError => e
      Result.new(output: "#{argv.first}: #{e.message}\n", status: 127)
    end

    # Runs +argv+ in +chdir+, with +env+ added to the environment and its
    # output going where ours goes, and returns its exit status.
    def stream(*argv, chdir:, env: {})
      system(@env.merge(env), [argv.first, argv.first], *argv.drop(1), chdir:)
      Process.last_status.exitstatus || 1
    end
  end

  # A step that failed, with the status the process ends with.
  class Failure < StandardError
    attr_reader :status

    def initialize(message, status)
      super(message)
      @status = status
    end
  end

  # The REUSE tool, at CI's version (ci.yml, "Install the REUSE tool").
  REUSE = "reuse[charset-normalizer]==6.2.0"

  # The libclang wheel's version, which bin/clang-headers unpacks the
  # headers of.
  LIBCLANG_VERSION = "18.1.1"

  # ci.yml's Rust components, which the Windows GNU toolchain gets too.
  COMPONENTS = %w[clippy rustfmt].freeze

  # What the stub in a clone's hooks folder says about itself. A hook of
  # anyone else's has no such line.
  MARKER = "# tokra pre-push stub, written by bin/setup"

  # The hook the stub hands off to, so every worktree has it.
  STUB = <<~STUB
    #!/bin/sh
    #{MARKER}
    hook="$(git rev-parse --show-toplevel)/.githooks/pre-push"
    [ -x "$hook" ] || exit 0
    exec "$hook" "$@"
  STUB

  USAGE = "usage: bin/setup [--gate]"

  # +root+ is the checkout, +env+ the environment to read (OS, CI, HOME,
  # XDG_CACHE_HOME, and the rest), +runner+ what runs a command (a
  # Shell, or whatever answers #capture and #stream), +out+ and +err+
  # where it says what it does and what is wrong, and +host_os+ Ruby's
  # name for the system.
  def initialize(root:, env:, runner: Shell.new(env: {}), out: $stdout, err: $stderr, host_os: RbConfig::CONFIG.fetch("host_os"))
    @root = root
    @env = env
    @runner = runner
    @out = out
    @err = err
    @host_os = host_os
  end

  # Sets up and returns the exit status: 0, 2 for a usage error, or the
  # status of the command that failed.
  def call(*args)
    gate = args == ["--gate"]
    unless gate || args.empty?
      @err.puts USAGE
      return 2
    end

    submodules
    locked { install_tools }
    install_bundle
    install_hooks unless gate
    0
  rescue Failure => e
    @err.puts "setup: #{e.message}"
    e.status
  end

  # Writes the pre-push stub into the clone's shared hooks folder, which
  # git reads from every worktree, unless a hook that is not Tokra's is
  # there. The hook it hands off to, .githooks/pre-push, runs the gate on
  # the commit you push. Writing the stub again changes nothing. A
  # clone's pre-commit, which refuses to install under core.hooksPath,
  # and a global hook that dispatches to .git/hooks keep working.
  def install_pre_push_stub
    hooks = File.join(probe("git", "rev-parse", "--path-format=absolute", "--git-common-dir").strip, "hooks")
    stub = File.join(hooks, "pre-push")
    if File.exist?(stub) && File.readlines(stub, chomp: true).none?(MARKER)
      @err.puts "#{stub} exists and is not Tokra's; leaving it, so git push will not run .githooks/pre-push."
    else
      FileUtils.mkdir_p(hooks)
      File.binwrite(stub, STUB)
      File.chmod(0o755, stub)
    end
    stub
  end

  private def windows?
    @env["OS"] == "Windows_NT"
  end

  private def ci?
    @env["CI"] == "true"
  end

  private def home
    @env["HOME"] || @env["USERPROFILE"]
  end

  # The cache folder the tools use: XDG_CACHE_HOME when set, else the
  # platform's own.
  private def cache_home
    xdg = @env["XDG_CACHE_HOME"].to_s
    return xdg unless xdg.empty?

    if windows?
      @env["LOCALAPPDATA"] || File.join(home, "AppData", "Local")
    elsif @host_os.include?("darwin")
      File.join(home, "Library", "Caches")
    else
      File.join(home, ".cache")
    end
  end

  # Where bin/clang-headers unpacks clang's headers, and bin/windows-env
  # reads them.
  private def clang_headers_dir
    cache = @env["XDG_CACHE_HOME"].to_s
    cache = File.join(home, ".cache") if cache.empty?
    File.join(cache, "tokra", "clang-#{LIBCLANG_VERSION}")
  end

  # Runs +argv+ and returns what it printed, for a question to ask of the
  # system; nothing is printed of it.
  private def probe(*argv, env: {})
    @runner.capture(*argv, chdir: @root, env:).output
  end

  private def probe_status(*argv, env: {})
    @runner.capture(*argv, chdir: @root, env:).status
  end

  # Prints +argv+ and runs it, or fails with its status.
  private def run(*argv, env: {})
    @out.puts "+ #{display(argv)}"
    @out.flush
    status = @runner.stream(*argv, chdir: @root, env:)
    raise Failure.new("#{display(argv)} failed with status #{status}", status) unless status.zero?
  end

  # +argv+ as one line, quoting only the words a person could not read
  # back as one.
  private def display(argv)
    argv.map { |word| word.match?(/[\s"'$\\]/) ? word.shellescape : word }.join(" ")
  end

  private def mise(*argv, env: {})
    run("mise", "x", "--", *argv, env:)
  end

  # What bin/clang-headers and bin/windows-env, which are sh scripts, need
  # on Windows: an sh and the tools beside it. A person's cmd.exe or
  # PowerShell has none on its PATH, unlike the MSYS2 bash this once ran
  # from, so where none is there, the sh of Git for Windows, which git
  # needs and a person has installed, goes ahead of the PATH, found from
  # the git on it. mise x puts its own tools ahead of both.
  private def sh_env
    return {} unless windows?

    path = @env["PATH"].to_s.split(";")
    return {} if path.any? { |dir| File.exist?(File.join(dir, "sh.exe")) }

    git = path.find { |dir| File.exist?(File.join(dir, "git.exe")) }
    return {} unless git

    bin = [File.join(git, ".."), File.join(git, "..", "..")].map { |root| File.expand_path(File.join(root, "usr", "bin")) }
      .find { |dir| File.exist?(File.join(dir, "sh.exe")) }
    bin ? { "PATH" => [bin.tr("/", "\\"), *path].join(";") } : {}
  end

  # vendor/tauri, which rake sync:tauri reads Tauri's JavaScript from.
  private def submodules
    return unless probe("git", "submodule", "status").each_line.any? { |line| line.start_with?("-", "+") }

    run("git", "submodule", "update", "--init")
  end

  # Two setups at once in one cache break mise's download store, so what
  # this file installs itself goes one setup at a time, under a lock on a
  # file in the cache folder. mise x installed the missing tools before
  # this file started, so no lock of this file's covers that first step.
  private def locked(&)
    lock = File.join(cache_home, "tokra", "setup.lock")
    FileUtils.mkdir_p(File.dirname(lock))
    File.open(lock, File::RDWR | File::CREAT, 0o644) do |file|
      file.flock(File::LOCK_EX)
      yield
    end
  end

  private def install_tools
    # Ruby, Rust, and Python, pinned in mise.toml. mise x installed what
    # was missing before this ran, so this matters for a run that is not
    # under mise x. Naming no tool installs each pin, whatever its os says.
    run("mise", "install") unless probe("mise", "ls", "--missing").strip.empty?
    install_gnu_toolchain if windows?
    install_python_package("reuse", REUSE, REUSE[/==(.*)/, 1])
    return unless windows?

    # libclang for bindgen, which reads Ruby's headers: LLVM's own build,
    # from PyPI's libclang wheel, where CI takes the runner's LLVM. The
    # wheel holds libclang alone, so clang's own headers come from LLVM's
    # clang source release of the same version (bin/clang-headers).
    install_python_package("libclang", "libclang==#{LIBCLANG_VERSION}", LIBCLANG_VERSION)
    mise("sh", "bin/clang-headers", env: sh_env) unless File.exist?(File.join(clang_headers_dir, "include", "stddef.h"))
  end

  # On Windows, mise's Ruby is RubyInstaller's, a MinGW build, which rb-sys
  # builds only with Rust's GNU target, so Cargo runs the GNU host
  # toolchain of mise.toml's Rust, with CI's components (ci.yml, "Read the
  # toolchain pins"). bin/windows-env selects it.
  private def install_gnu_toolchain
    rust = File.read(File.join(@root, "mise.toml"))[/^rust = "([^"]*)"/, 1]
    toolchain = "#{rust}-x86_64-pc-windows-gnu"
    listed = probe("mise", "x", "--", "rustup", "toolchain", "list").lines.map { |line| line.split.first }
    return if listed.include?(toolchain) && components_installed?(toolchain)

    args = COMPONENTS.flat_map { |name| ["--component", name] }
    mise("rustup", "toolchain", "install", toolchain, "--profile", "minimal", *args)
  end

  private def components_installed?(toolchain)
    installed = probe("mise", "x", "--", "rustup", "component", "list", "--installed", "--toolchain", toolchain)
    COMPONENTS.all? { |name| installed.include?("#{name}-#{toolchain}") }
  end

  private def install_python_package(name, requirement, version)
    shown = probe("mise", "x", "--", "python", "-m", "pip", "show", name)
    return if shown[/^Version: (\S+)/, 1] == version

    mise("python", "-m", "pip", "install", "--quiet", requirement)
  end

  # A CI runner installs the bundle as ci.yml does: frozen to Gemfile.lock,
  # in vendor/bundle, which a runner that keeps its checkout or caches that
  # folder has from its last run. The bundle compiles Rust gems, which on
  # Linux link the Linux packages and on Windows build with what
  # bin/windows-env sets.
  private def install_bundle
    configure_ci_bundle if ci?
    through = windows? ? ["sh", "bin/windows-env"] : ["bin/linux-env"]
    return if probe_status("mise", "x", "--", *through, "bundle", "check", env: sh_env).zero?

    mise(*through, "bundle", "install", env: sh_env)
  end

  private def configure_ci_bundle
    # A bundle left half written, a gem's specification without its files,
    # stops Bundler from starting at all once the Bundler the lockfile
    # names is among them: RubyGems finds the specification and cannot load
    # the gem. Nothing repairs that in place, so the folder goes, and the
    # install makes it again.
    bundle = File.join(@root, "vendor", "bundle")
    if !probe_status("mise", "x", "--", "bundle", "--version").zero? && File.exist?(bundle)
      @out.puts "+ rm -rf vendor/bundle"
      FileUtils.rm_rf(bundle)
    end
    configured = begin
      File.read(File.join(@root, ".bundle", "config"))
    rescue SystemCallError
      ""
    end
    mise("bundle", "config", "set", "--local", "path", "vendor/bundle") unless configured.match?(%r{^BUNDLE_PATH: "vendor/bundle"\s*$})
    mise("bundle", "config", "set", "--local", "frozen", "true") unless configured.match?(/^BUNDLE_FROZEN: "true"\s*$/)
  end

  # The rest is for a clone a person works in, not for the gate.
  private def install_hooks
    install_pre_push_stub
    # Where core.hooksPath is set, git runs the hooks in that folder and
    # never this clone's, so the stub runs only if the pre-push hook there
    # hands off to it, and pre-commit refuses to install its own. A CI
    # runner commits nothing and reads no documentation. mise.toml leaves
    # pre-commit off Windows, where mise installs it only through pipx.
    hooks_path = probe("git", "config", "--get", "core.hooksPath").strip
    if !hooks_path.empty?
      stub = File.join(probe("git", "rev-parse", "--path-format=absolute", "--git-common-dir").strip, "hooks", "pre-push")
      @err.puts "core.hooksPath is set, so git runs the hooks in #{hooks_path}, not this clone's:"
      @err.puts "git push runs .githooks/pre-push only if the pre-push hook there runs #{stub},"
      @err.puts "and pre-commit's hook is not installed."
    elsif !ci? && !windows?
      mise("pre-commit", "install")
    end
    mise("bundle", "exec", "rake", "rdoc") unless ci?
  end
end

if $PROGRAM_NAME == __FILE__
  $stdout.sync = true
  root = File.expand_path("..", __dir__)
  exit Setup.new(root:, env: ENV.to_h, runner: Setup::Shell.new(env: {})).call(*ARGV)
end
