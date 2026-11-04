# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "digest"
require "English"
require "fileutils"
require "open3"
require "tmpdir"
require_relative "real_windows"

# Runs the real-window tests, except RealWindows::CONSOLE, in the hidden
# +tokratest+ session, from the maintainer's own, and streams what they
# print (Plans 056 and 057).
#
# It follows the hidden session's RECIPE.txt. Here, in the maintainer's
# session: ask the runner whether it answers, publish the checkout with
# +stage+, install the shared tools and gems it names if any is missing,
# and read their variables from +toolchain-env+. There, as tokratest:
# copy the published checkout into the account's own mirror, and run the
# real-window tasks in it with TOKRA_REAL_WINDOWS=local, through
# <tt>bundle exec</tt> only, since the shared gems are read-only there.
#
# Each checkout has a published copy and a mirror of its own (#place), so
# gates of several checkouts run at once; gates of one checkout take
# turns. Each step's failure raises Failure, whose message says what
# happened; a runner that does not answer is one, and nothing falls back
# to running the tests in this session.
#
# === Example
#
#   HiddenJob.new(checkout: Dir.pwd).run
class HiddenJob
  # Why the job did not run, or did not pass.
  class Failure < StandardError; end

  # Where one checkout is published (+source+, which every account reads)
  # and mirrored (+mirror+, in the account's home).
  Place = Data.define(:source, :mirror)

  # Tokra's test account.
  ACCOUNT = "tokratest"

  # The project's name, for stage, toolchain-env, and hidden-tools-install.
  PROJECT = "tokra"

  # The scripts the test accounts run, as install-shared publishes them.
  SHARED = "/Users/Shared/hidden-session"

  # Where stage publishes, the one place the test accounts read a
  # project from.
  SOURCES = "/Users/Shared/hidden-src"

  # The account's home, which holds each checkout's mirror. mirror leaves
  # a copy's target/ and tmp/ alone, so Cargo's builds there are the
  # account's own and persist.
  HOME = "/Users/#{ACCOUNT}".freeze

  # Cargo writes its registry and builds here, so it is the account's own.
  CARGO_HOME = "#{HOME}/.cargo".freeze

  # Files git tracks whose names only look like credentials, which stage
  # otherwise refuses to publish: a Rails example's encrypted credentials,
  # a Tauri source file about tokens, and Tauri's updater test keys.
  STAGE_ALLOW = %w[
    examples/verify_rails_sqlite/config/credentials.yml.enc
    vendor/tauri/crates/tauri-utils/src/tokens.rs
    vendor/tauri/crates/tauri/test/updater/fixture/*
  ].freeze

  # Memory that must be free for the job to start, in gigabytes.
  MIN_FREE_GB = 20

  # Seconds the copy and the tests may take; a cold build of the extension
  # comes first.
  MIRROR_TIMEOUT = 1800
  RUN_TIMEOUT = 5400

  # The tasks that run in the mirror.
  TASKS = %w[test:keyboard test:real_windows].freeze

  # Whether the plugins' real-window tests run in the job too. They can
  # since hidden-tools-install shares every tracked Gemfile.lock's gems
  # (hidden_session 39234ea); false leaves them out, and says so.
  PLUGINS = true

  # The task that runs the plugins' real-window tests.
  PLUGIN_TASK = "test:real_windows:plugins"

  # How much of a step's output is kept, for the path it says last.
  TAIL = 65_536

  # What each of hidden-run's own exit statuses means.
  STATUSES = {
    69 => "the runner never took the job (hidden-run exit 69), so nothing ran there: this is no pass. " \
      "Is #{ACCOUNT} logged in? See hidden-status.",
    70 => "the runner refused the job (hidden-run exit 70; its reason is above)",
    75 => "too little memory is free, so the job never started (hidden-run exit 75, --min-free-gb " \
      "#{MIN_FREE_GB}); see hidden-status, and try again later",
    124 => "the job ran past its timeout and was stopped (hidden-run exit 124)",
    130 => "the job was interrupted (hidden-run exit 130)",
  }.freeze

  # +scripts+ is the hidden session's folder of scripts, and +checkout+
  # the checkout to publish. +plugins+ says whether the plugins'
  # real-window tests run too. +sources+ is where stage publishes, and
  # +tools_lock+ the file that keeps two checkouts' installs of the one
  # shared bundle apart. Output goes to +out+.
  def initialize(checkout:, scripts: self.class.scripts, out: $stdout, plugins: PLUGINS, sources: SOURCES,
    tools_lock: File.join(Dir.tmpdir, "tokra-hidden-tools.lock")
  )
    @checkout = checkout
    @scripts = scripts
    @out = out
    @plugins = plugins
    @sources = sources
    @tools_lock = tools_lock
  end

  # The hidden session's scripts: TOKRA_HIDDEN_SESSION, or the
  # maintainer's checkout of them.
  def self.scripts(env = ENV)
    env.fetch("TOKRA_HIDDEN_SESSION") { File.expand_path("~/Developer/hidden_session") }
  end

  # A name for the checkout at +path+, the same each time and unlike any
  # other checkout's: its folder's name and a digest of its whole path.
  def self.slug(path)
    "#{File.basename(path).downcase.gsub(/[^a-z0-9_-]+/, '-')}-#{Digest::SHA256.hexdigest(path)[0, 8]}"
  end

  # Where this checkout is published and mirrored: one copy and one
  # mirror for each checkout, so that gates of several run at once. This
  # is the method to change should the hidden session place them
  # otherwise.
  def place
    slug = self.class.slug(@checkout)
    Place.new(source: File.join(@sources, "#{PROJECT}-#{slug}"), mirror: "#{HOME}/#{PROJECT}-mirror-#{slug}")
  end

  # Runs the real-window tests in tokratest, and raises Failure unless
  # they ran and passed. A second gate of the same checkout waits.
  def run
    ping
    locked(File.join(@checkout, "tmp/hidden-job.lock"), "another hidden gate of this checkout") do
      staged = publish
      environment = environment(staged)
      step("the real-window tests in #{ACCOUNT}", job(mirror(staged), environment))
    end
    return if @plugins

    @out.puts "== test:hidden: the plugins' real-window tests did NOT run (HiddenJob::PLUGINS is false). " \
      "To run them here: TOKRA_REAL_WINDOWS=local rake #{PLUGIN_TASK}"
  end

  # The command that runs TASKS in +mirrored+, with +environment+ (the
  # <tt>--env</tt> options of toolchain-env).
  def job(mirrored, environment)
    tasks = @plugins ? [*TASKS, PLUGIN_TASK] : TASKS
    hidden_run("--timeout", RUN_TIMEOUT.to_s, "--min-free-gb", MIN_FREE_GB.to_s, "--cwd", mirrored,
      *environment, "--env", "CARGO_HOME=#{CARGO_HOME}", "--env", "TOKRA_QUIET=1",
      "--env", "TOKRA_REAL_WINDOWS=local", "--env", "#{RealWindows::HIDDEN_JOB}=1", "--", "bundle", "exec", "rake", *tasks)
  end

  # Removes the published copy and the mirror of every checkout whose
  # folder is gone, as stage's <tt>.stage</tt> record names it, and
  # returns the copies it removed.
  def prune
    gone = Dir[File.join(@sources, "#{PROJECT}-*")].select do |source|
      record = File.join(source, ".stage")
      checkout = File.exist?(record) && File.read(record)[/^checkout=(.*)$/, 1]
      checkout && !File.directory?(checkout)
    end
    gone.each do |source|
      mirror = "#{HOME}/#{PROJECT}-mirror-#{File.basename(source).delete_prefix("#{PROJECT}-")}"
      step("remove #{mirror}", hidden_run("--", "/bin/rm", "-rf", mirror))
      @out.puts "== test:hidden:prune: remove #{source}"
      FileUtils.rm_rf(source)
    end
  end

  private def here = "set TOKRA_REAL_WINDOWS=local to open the real windows in this session instead"

  private def ping
    path = File.join(@scripts, "hidden-run")
    raise Failure, "no hidden-run at #{path}, so the real-window tests cannot run hidden; #{here}" unless File.executable?(path)
    return if stream([path, "--account", ACCOUNT, "--ping"]).first.success?

    raise Failure, "#{ACCOUNT}'s hidden session is not answering (hidden-run --ping), so the real-window " \
      "tests did not run; see hidden-status, or #{here}"
  end

  # Publishes the checkout where the test account can read it, and
  # returns the published copy.
  private def publish
    allows = STAGE_ALLOW.flat_map { |pattern| ["--allow", pattern] }
    said = last_said(step("stage", [script("stage"), "--to", place.source, *allows, PROJECT, @checkout]), "stage")
    said || raise(Failure, "stage did not say where it published #{@checkout}")
  end

  # Copies the published copy into the account's mirror, and returns
  # where to run in it.
  private def mirror(staged)
    lines = step("mirror", hidden_run("--timeout", MIRROR_TIMEOUT.to_s, "--", "#{SHARED}/mirror", staged, place.mirror))
    last_said(lines, "mirror") || raise(Failure, "mirror did not say where it copied #{staged}")
  end

  # toolchain-env's options for +staged+, once what it names is installed.
  private def environment(staged)
    install(staged)
    outside_home(toolchain(staged) || raise(Failure, "toolchain-env #{PROJECT} failed (its reason is above)"))
  end

  private def toolchain(staged)
    printed, said, status = Open3.capture3(script("toolchain-env"), PROJECT, staged)
    @out.print said
    return unless status.success?

    # hidden-run sets the account's own lock, which one of ours would replace.
    printed.lines(chomp: true).each_slice(2).reject { |_, value| value.to_s.start_with?("DESKTOP_INPUT_LOCK=") }
      .flatten
  end

  # Installs the shared tools and gems the published copy names, when
  # hidden-tools-install --check finds any missing. Every checkout shares
  # one bundle, so installs take turns; and one that leaves something
  # missing fails the job.
  private def install(staged)
    installer = script("hidden-tools-install")
    check = [installer, "--check", "--staged", staged, PROJECT]
    locked(@tools_lock, "another checkout's hidden-tools-install") do
      @out.puts "== test:hidden: hidden-tools-install --check"
      next if stream(check).first.success?

      step("hidden-tools-install", [installer, "--staged", staged, PROJECT])
      step("hidden-tools-install --check, after installing", check)
    end
  end

  # Runs the block holding an exclusive lock on the file at +path+,
  # saying so first if +holder+ has it.
  private def locked(path, holder)
    FileUtils.mkdir_p(File.dirname(path))
    File.open(path, File::RDWR | File::CREAT, 0o644) do |lock|
      unless lock.flock(File::LOCK_EX | File::LOCK_NB)
        @out.puts "== test:hidden: waiting for #{holder} (#{path})"
        lock.flock(File::LOCK_EX)
      end
      yield
    end
  end

  private def hidden_run(*args) = [script("hidden-run"), "--account", ACCOUNT, "--merge", *outside_home(args)]

  # +args+, unless one names the maintainer's home, which the account
  # cannot open.
  private def outside_home(args)
    home = Dir.home
    named = args.find { |arg| arg.include?("#{home}/") || arg.end_with?(home) }
    raise Failure, "#{named} names #{home}, which #{ACCOUNT} cannot open" if named

    args
  end

  # Runs +argv+, printing what it prints, and returns the lines it ended
  # with, or raises Failure saying what +name+'s status means.
  private def step(name, argv)
    @out.puts "== test:hidden: #{name}"
    status, tail = stream(argv)
    return tail.scrub.lines(chomp: true) if status.success?

    raise Failure, "#{name}: #{ending(status)}"
  end

  private def ending(status)
    return "killed by SIG#{Signal.signame(status.termsig)}" if status.signaled?

    STATUSES.fetch(status.exitstatus) { "failed (exit #{status.exitstatus})" }
  end

  # Runs +argv+, passing on what it prints as it prints it, a dot at a
  # time, and returns its status and the last TAIL bytes it printed.
  private def stream(argv)
    tail = +""
    IO.popen(argv, err: %i[child out]) do |io|
      loop do
        chunk = io.readpartial(4096).force_encoding(Encoding::UTF_8)
        @out.write(chunk)
        @out.flush
        tail << chunk
        tail = tail.byteslice(-TAIL, TAIL) if tail.bytesize > TAIL
      end
    rescue EOFError
      nil
    end
    [$CHILD_STATUS, tail]
  end

  # The path in the last "NAME: /PATH" line of +lines+.
  private def last_said(lines, name)
    lines.reverse_each.lazy.filter_map { |line| line[%r{\A#{name}: (/\S*)\z}, 1] }.first
  end

  # The hidden session's script +name+, which must be there.
  private def script(name)
    path = File.join(@scripts, name)
    return path if File.executable?(path)

    raise Failure, "no #{name} at #{path}: is the hidden session's checkout there (TOKRA_HIDDEN_SESSION)?"
  end
end
