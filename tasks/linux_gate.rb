# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "json"
require "open3"
require "shellwords"
require "yaml"
require_relative "hidden_job"

# Runs CI's Linux job in a Docker container on this machine, before a
# push (Plan 058).
#
# The maintainer's gate runs on a Mac, where the tests that skip off
# Linux never run. This builds an image like CI's runner from
# tasks/linux/Dockerfile, mounts the checkout read-only, copies what git
# tracks into the container (::snapshot), and runs there the steps
# ci.yml's Linux job runs, read from ci.yml: the frozen bundle install and
# the gate under Xvfb and D-Bus. Linux windows in the container never
# reach the maintainer's session, so the real-window tests run there too.
#
# Each checkout has its own image tag, container, and volumes, keyed by
# HiddenJob.slug, so runs of several checkouts go at once and a second
# run is warm. Each step's failure raises Failure.
#
# === Example
#
#   LinuxGate.new(checkout: Dir.pwd).run
class LinuxGate
  # Why the run did not start, or did not pass.
  class Failure < StandardError; end

  # The build context, which holds the Dockerfile and nothing else.
  CONTEXT = File.join(__dir__, "linux")

  # What every image, container, and volume name starts with.
  PREFIX = "tokra-linux"

  # The label naming the checkout a volume belongs to, for #prune.
  LABEL = "dev.tokra.checkout"

  # Where the container reads the checkout, read-only, and works on its
  # copy.
  SOURCE = "/src"
  WORK = "/work"

  # The container user's home.
  HOME = "/home/tokra"

  # Each volume's key and where it is mounted: Cargo's registry, the
  # plugins' gems, the root bundle (where ci.yml puts it), and the build
  # outputs.
  VOLUMES = {
    "cargo" => "#{HOME}/.cargo",
    "gems" => "#{HOME}/gems",
    "bundle" => "#{WORK}/vendor/bundle",
    "target" => "#{WORK}/target",
    "tmp" => "#{WORK}/tmp",
  }.freeze

  # The volumes that hold build outputs, which a clean run empties first.
  BUILDS = %w[target tmp].freeze

  # WebKitGTK's page processes share memory through /dev/shm, which
  # Docker otherwise caps at 64 MB.
  SHM_SIZE = "1g"

  # The container's environment. GitHub Actions sets CI=true on every
  # runner, not ci.yml, and RealWindows.where and KeyboardNotice read it.
  # TOKRA_QUIET=1 is this task's own, which CI does not set: it silences
  # the console tests' notice, which on Linux says nothing anyway.
  ENVIRONMENT = { "CI" => "true", "TOKRA_QUIET" => "1" }.freeze

  # The ci.yml steps this reads: the Linux packages, the REUSE tool, the
  # bundle, and the gate on Linux.
  APT_STEP = "Install GTK, WebKitGTK, and a display server"
  REUSE_STEP = "Install the REUSE tool"
  BUNDLE_STEP = "Install the bundle"
  GATE_STEP = "Run the gate under X11"

  # The action ci.yml installs Rust with, whose components it names.
  RUST_ACTION = "dtolnay/rust-toolchain"

  # The git mode of a submodule's entry.
  GITLINK = "160000"

  # The variables a git hook passes to the commands it runs, which point
  # every git below it at the hook's repository and index; a git run in a
  # submodule would read the superproject's index. Each git here finds its
  # repository from the folder it runs in instead.
  GIT_PLACE = %w[
    GIT_DIR
    GIT_INDEX_FILE
    GIT_WORK_TREE
    GIT_PREFIX
    GIT_COMMON_DIR
    GIT_OBJECT_DIRECTORY
    GIT_ALTERNATE_OBJECT_DIRECTORIES
].to_h { |name| [name, nil] }.freeze

  # Git as the snapshot runs it: who commits, none of a person's hooks or
  # signing, and every path taken literally, never as a pattern.
  GIT = [
    "git",
    "--literal-pathspecs",
    *%w[
      user.name=tokra
      user.email=tokra@localhost
      init.defaultBranch=trunk
      advice.addEmbeddedRepo=false
      commit.gpgSign=false
      core.hooksPath=/dev/null
    ].flat_map { |setting| ["-c", setting] },
  ].freeze

  # +checkout+ is the checkout to run, +docker+ the Docker command, and
  # +out+ where the task's own lines go.
  def initialize(checkout:, docker: "docker", out: $stdout)
    @checkout = checkout
    @docker = docker
    @out = out
  end

  # The checkout's name in every image, container, and volume name.
  def slug = HiddenJob.slug(@checkout)

  # The container's name, which is also each volume's prefix.
  def name = "#{PREFIX}-#{slug}"

  # The image's tag.
  def image = "#{PREFIX}:#{slug}"

  # Each volume's name, and where it is mounted.
  def volumes = VOLUMES.transform_keys { |key| "#{name}-#{key}" }

  # The pins the image takes, read from the files CI reads them from.
  def build_args
    {
      "RUST_VERSION" => mise("rust"),
      "RUST_COMPONENTS" => rust_components,
      "APT_PACKAGES" => apt_packages.join(" "),
      "REUSE_REQUIREMENT" => reuse_requirement,
      "BUNDLER_VERSION" => bundler_version,
    }
  end

  # The command that builds the image.
  def build_command
    args = build_args.flat_map { |key, value| ["--build-arg", "#{key}=#{value}"] }
    [@docker, "build", "--progress", "plain", "--tag", image, *args, CONTEXT]
  end

  # The commands that create the volumes, each labeled with the checkout.
  # Creating one that exists changes nothing.
  def volume_commands
    volumes.keys.map { |volume| [@docker, "volume", "create", "--label", "#{LABEL}=#{@checkout}", volume] }
  end

  # The commands that remove the build volumes, so a clean run builds
  # everything again, as CI does without its caches.
  def clean_commands
    BUILDS.map { |key| [@docker, "volume", "rm", "--force", "#{name}-#{key}"] }
  end

  # The command that runs +tasks+ in the container, or the whole gate
  # with none. It reads #manifest on its standard input.
  def run_command(tasks = [])
    if (character = [",", '"'].find { |unsafe| @checkout.include?(unsafe) })
      raise Failure, "#{@checkout} has #{character.inspect} in its path, which docker run --mount cannot take"
    end

    mounts = [
      "type=bind,source=#{@checkout},target=#{SOURCE},readonly",
      *volumes.map { |volume, path| "type=volume,source=#{volume},target=#{path}" },
    ]
    options = mounts.flat_map { |mount| ["--mount", mount] } +
      ENVIRONMENT.flat_map { |key, value| ["--env", "#{key}=#{value}"] }
    container = ["--rm", "--interactive", "--init", "--name", name, "--shm-size", SHM_SIZE]
    [@docker, "run", *container, *options, "--workdir", WORK, image, "bash", "-c", script(tasks)]
  end

  # What the container runs: the snapshot, then ci.yml's bundle install
  # and its gate on Linux, with +tasks+ after it, each command only if the
  # one before it passed.
  def script(tasks = [])
    snapshot = "LinuxGate.snapshot(JSON.parse($stdin.read), from: #{SOURCE.dump}, to: #{WORK.dump})"
    [
      "ruby -I#{SOURCE}/tasks -rlinux_gate -e #{Shellwords.escape(snapshot)}",
      *bundle_commands,
      "exec #{Shellwords.join([*gate_command, *tasks])}",
    ].join(" && ")
  end

  # The files to copy: what git tracks, as the working tree has them,
  # less any it has deleted, and each submodule's the same way, relative
  # to it. A submodule whose HEAD is not the commit the checkout records
  # is copied as it is, and said so.
  def manifest
    files = []
    submodules = {}
    git_lines(@checkout, "ls-files", "-z", "--stage").each do |entry|
      meta, path = entry.split("\t", 2)
      mode, recorded = meta.split
      if mode == GITLINK
        submodules[path] = submodule_files(path, recorded)
      else
        files << path
      end
    end
    { "files" => present(@checkout, files), "submodules" => submodules }
  end

  # Builds the image, creates the volumes (emptying the build volumes
  # first if +clean+), and runs +tasks+ (or the whole gate) in the
  # container, raising Failure unless they pass.
  def run(tasks = [], clean: false)
    taken = capture(@docker, "ps", "--all", "--quiet", "--filter", "name=^#{name}$").strip
    unless taken.empty?
      raise Failure, "container #{name} exists, so another test:linux of this checkout is running; " \
        "wait for it, or remove a stale one with: docker rm --force #{name}"
    end

    step("build #{image}", build_command)
    clean_commands.each { |command| step("empty #{command.last}", command, quiet: true) } if clean
    volume_commands.each { |command| step("volume #{command.last}", command, quiet: true) }
    manifest = JSON.generate(self.manifest)
    step("#{tasks.empty? ? 'the gate' : tasks.join(' ')} in #{name}", run_command(tasks), input: manifest)
  end

  # Removes the volumes and image of every checkout whose folder is gone,
  # as each volume's label names it, saying each it removes, and returns
  # them. A volume it cannot remove fails the prune, once it has tried
  # every other.
  def prune
    listed = capture(@docker, "volume", "ls", "--filter", "label=#{LABEL}", "--format", "{{.Name}}\t{{.Label \"#{LABEL}\"}}")
    gone = listed.lines(chomp: true).map { |line| line.split("\t", 2) }.reject { |_, path| File.directory?(path.to_s) }
    removed = []
    failed = []
    gone.each do |volume, _|
      printed, status = Open3.capture2e(@docker, "volume", "rm", volume)
      if status.success?
        @out.puts "== test:linux:prune: removed #{volume}"
        removed << volume
      else
        failed << "#{volume} (#{printed.strip})"
      end
    end
    gone.map { |volume, _| volume[/\A#{PREFIX}-(.+)-[a-z]+\z/o, 1] }.uniq.each do |key|
      system(@docker, "image", "rm", "#{PREFIX}:#{key}", out: File::NULL, err: File::NULL)
    end
    raise Failure, "could not remove #{failed.join(', ')}" unless failed.empty?

    removed
  end

  # Copies the files +manifest+ names from +from+ to +to+, keeping their
  # modes, times, and symlinks, and commits them into a new repository
  # there, each submodule as a repository of its own that the outer one
  # records as a gitlink. The container runs this, from the read-only
  # checkout.
  def self.snapshot(manifest, from:, to:)
    manifest.fetch("submodules").each do |submodule, files|
      files.each { |file| copy(File.join(from, submodule, file), File.join(to, submodule, file)) }
      commit(File.join(to, submodule), files)
    end
    files = manifest.fetch("files")
    files.each { |file| copy(File.join(from, file), File.join(to, file)) }
    commit(to, files + manifest.fetch("submodules").keys)
  end

  def self.copy(source, destination)
    FileUtils.mkdir_p(File.dirname(destination))
    if File.symlink?(source)
      File.symlink(File.readlink(source), destination)
    else
      FileUtils.copy_file(source, destination)
      stat = File.stat(source)
      File.chmod(stat.mode & 0o7777, destination)
      File.utime(stat.atime, stat.mtime, destination)
    end
  rescue Errno::ENOENT
    raise Failure, "#{source} is gone: the checkout changed while test:linux copied it, so run it again"
  end
  private_class_method :copy

  def self.commit(dir, paths)
    git(dir, "init", "--quiet")
    git(dir, "add", "--force", "--pathspec-from-file=-", "--pathspec-file-nul", input: paths.join("\0"))
    git(dir, "commit", "--quiet", "--no-verify", "--message", "snapshot")
  end
  private_class_method :commit

  def self.git(dir, *args, input: "")
    said, status = Open3.capture2e(GIT_PLACE, *GIT, *args, stdin_data: input, chdir: dir)
    raise Failure, "git #{args.first} failed in #{dir}: #{said}" unless status.success?
  end
  private_class_method :git

  private def submodule_files(path, recorded)
    dir = File.join(@checkout, path)
    unless File.exist?(File.join(dir, ".git"))
      raise Failure, "#{path} is not checked out, and CI checks it out. Run: git submodule update --init"
    end

    head = git_lines(dir, "rev-parse", "HEAD").first.to_s.strip
    unless head == recorded
      @out.puts "== test:linux: #{path} is at #{head[0, 12]}, not the #{recorded[0, 12]} the checkout records; " \
        "the container gets its working tree, which CI would not (git submodule update)"
    end
    present(dir, git_lines(dir, "ls-files", "-z", "--cached"))
  end

  # The +paths+ under +dir+ that the working tree still has.
  private def present(dir, paths)
    paths.select do |path|
      full = File.join(dir, path)
      File.symlink?(full) || File.file?(full)
    end
  end

  private def git_lines(dir, *args)
    printed, status = Open3.capture2(GIT_PLACE, "git", *args, chdir: dir)
    raise Failure, "git #{args.join(' ')} failed in #{dir}" unless status.success?

    printed.split("\0")
  end

  # mise.toml's pin for +tool+, as ci.yml reads it.
  private def mise(tool)
    File.read(File.join(@checkout, "mise.toml"))[/^#{tool} = "(.*)"$/, 1] ||
      raise(Failure, "mise.toml pins no #{tool}")
  end

  private def workflow_steps
    workflow = YAML.safe_load_file(File.join(@checkout, ".github/workflows/ci.yml"))
    workflow.fetch("jobs").values.flat_map { |job| job.fetch("steps", []) }
  end

  private def workflow_step(name)
    workflow_steps.find { |step| step["name"] == name } || raise(Failure, "ci.yml has no step named #{name.inspect}")
  end

  # The packages ci.yml's install step names after its options: the
  # apt-get install line and the lines its backslashes continue it onto.
  private def apt_packages
    lines = workflow_step(APT_STEP).fetch("run").lines(chomp: true)
    start = lines.index { |line| line.match?(/\bapt-get install\b/) } ||
      raise(Failure, "ci.yml's #{APT_STEP.inspect} step runs no apt-get install")
    command = [lines[start]]
    command << lines.fetch(start + command.size, "") while command.last.end_with?("\\")
    words = Shellwords.split(command.join("\n").gsub("\\\n", " "))
    words.drop(words.index("install") + 1).reject { |word| word.start_with?("-") }
  end

  private def reuse_requirement
    run = workflow_step(REUSE_STEP).fetch("run")
    Shellwords.split(run).find { |word| word.start_with?("reuse") } ||
      raise(Failure, "ci.yml's #{REUSE_STEP.inspect} step installs no reuse")
  end

  # The Rust components ci.yml's toolchain step installs, for rustup.
  private def rust_components
    step = workflow_steps.find { |each| each["uses"].to_s.start_with?("#{RUST_ACTION}@") } ||
      raise(Failure, "ci.yml installs no Rust with #{RUST_ACTION}")
    step.dig("with", "components").to_s.split(",").map(&:strip).reject(&:empty?).join(",")
  end

  # ci.yml's commands that install the bundle.
  private def bundle_commands = workflow_step(BUNDLE_STEP).fetch("run").lines(chomp: true).map(&:strip).reject(&:empty?)

  # ci.yml's command that runs the gate on Linux.
  private def gate_command = Shellwords.split(workflow_step(GATE_STEP).fetch("run"))

  private def bundler_version
    File.read(File.join(@checkout, "Gemfile.lock"))[/^BUNDLED WITH\n\s+(\S+)/, 1] ||
      raise(Failure, "Gemfile.lock names no Bundler")
  end

  private def capture(*argv)
    printed, status = Open3.capture2(*argv)
    raise Failure, "#{argv.join(' ')} failed; is Docker running?" unless status.success?

    printed
  end

  # Runs +argv+, with +input+ on its standard input, and raises Failure
  # saying what +name+'s status means. What it prints goes where the
  # task's own lines do, as it prints it, or if +quiet+ only when it fails.
  private def step(name, argv, input: nil, quiet: false)
    if quiet
      printed, status = Open3.capture2e(*argv)
      @out.print printed unless status.success?
    else
      @out.puts "== test:linux: #{name}"
      status = stream(argv, input)
    end
    raise Failure, "#{name} #{ending(status)}" unless status.success?
  end

  private def stream(argv, input)
    Open3.popen2e(*argv) do |stdin, output, wait|
      writer = Thread.new do
        stdin.write(input) if input
      rescue Errno::EPIPE
        nil
      ensure
        stdin.close
      end
      loop do
        @out.write(output.readpartial(4096))
        @out.flush
      end
    rescue EOFError
      writer.join
      wait.value
    end
  end

  private def ending(status)
    return "was killed by SIG#{Signal.signame(status.termsig)}" if status.signaled?

    "failed (exit #{status.exitstatus})"
  end
end
