# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "digest"
require "fileutils"
require "open3"
require_relative "linux_gate"

# Runs a command with the Linux packages ci.yml installs, on a Debian or
# Ubuntu machine where you cannot install them (Plan 068).
#
# Tokra links WebKitGTK, GTK 3, and libsoup, and its tests drive them
# under Xvfb with xdotool and dunst. CI installs these with sudo. Without
# root, nothing compiles.
#
# This class asks apt what an install would bring, fetches those packages
# with apt-get download, which checks each against the distribution's
# signed package lists, and unpacks them under tmp/linux-env. It joins
# them with the system's /usr and /etc in a tree of symbolic links, and
# runs the command under bubblewrap with that tree bound over /usr and
# /etc. Every file then sits where its package put it, so WebKitGTK finds
# its helper processes at the paths compiled into it.
#
# Where nothing is missing, as on CI, it runs the command unchanged. A
# second run with nothing changed reuses the build.
#
# === Example
#
#   exec(*LinuxEnv.new(checkout: Dir.pwd).command(%w[bundle exec rake]))
class LinuxEnv
  # Why the packages could not be brought.
  class Failure < StandardError; end

  # A package apt would install: its name, version, and architecture.
  class Package < Data.define(:name, :version, :arch)
    # The argument apt-get download takes for exactly this version.
    def spec
      "#{name}=#{version}"
    end

    # The file apt-get download writes, which escapes an epoch's colon.
    def deb
      "#{name.split(':').first}_#{version.gsub(':', '%3a')}_#{arch}.deb"
    end
  end

  # dpkg's record of what is installed.
  STATUS = "/var/lib/dpkg/status"

  # Set under bwrap to the build in use, so a command run there runs as is.
  VARIABLE = "TOKRA_LINUX_ENV"

  # The folders a package's files are bound over. A merged /usr system's
  # /bin, /sbin, and /lib are links into /usr.
  TOPS = %w[usr etc].freeze

  # Folders a merged /usr system keeps as links into /usr.
  MERGED = %w[bin sbin lib lib32 lib64 libx32].freeze

  # Bumped when the layout of a build changes, so old builds are not used.
  LAYOUT = "1"

  # An Inst line of apt-get --simulate: the package, the version it
  # replaces if any, then the version and, last in brackets, the
  # architecture.
  INST = /^Inst (\S+) (?:\[[^\]]*\] )?\((\S+) [^\n]*\[([^\]\n]+)\]\)/

  # [checkout] The repository's folder; builds go in its tmp/linux-env.
  # [packages] The apt packages to have, by default those ci.yml installs.
  # [linux] Whether this is Linux.
  # [status] dpkg's status file, whose changes mean a new build.
  # [host] The system's root folder, which the tree of links joins.
  # [env] The environment the tools run with and the command checks.
  # [err] Where it says what it fetches.
  def initialize(checkout:, packages: nil, linux: RUBY_PLATFORM.include?("linux"), status: STATUS, host: "/",
    env: ENV, err: $stderr
  )
    @checkout = checkout
    @packages = packages
    @linux = linux
    @status = status
    @host = host
    @env = env
    @err = err
    @home = File.join(checkout, "tmp", "linux-env")
  end

  # The apt packages to have: those ci.yml's install step names, unless
  # given. Read only on Linux.
  def packages
    @packages ||= LinuxGate.new(checkout: @checkout).apt_packages
  end

  # The command to run for +argv+: +argv+ itself where nothing is
  # missing, and otherwise +argv+ under bwrap, after bringing the packages.
  def command(argv)
    return argv unless missing?

    bwrap(prepare) + argv
  end

  # The packages apt-get --simulate's +text+ would install.
  def self.simulated(text)
    text.scan(INST).map { |name, version, arch| Package.new(name:, version:, arch:) }
  end

  # Moves what a package ships in /bin, /sbin, or /lib under +root+ into
  # usr/, where the system's link to /usr would have put it.
  def self.merge_usr(root, host: "/")
    MERGED.each do |top|
      from = File.join(root, top)
      next unless File.directory?(from) && File.symlink?(File.join(host, top))

      move(from, File.join(root, "usr", top))
    end
  end

  # Makes +dest+ a tree of links that joins +ours+ and +host+. Where both
  # have a folder it recurses; where both have anything else, ours wins.
  # A link is copied as it is, and anything else of the host's links to
  # its place under +link+, where the host's folder is bound.
  def self.farm(dest, ours:, host:, link:)
    Dir.mkdir(dest)
    (children(ours) | children(host)).sort.each do |name|
      mine = File.join(ours, name)
      theirs = File.join(host, name)
      place = File.join(dest, name)
      if File.directory?(mine) && !File.symlink?(mine) && File.directory?(theirs)
        farm(place, ours: mine, host: theirs, link: File.join(link, name))
      elsif present?(mine)
        File.symlink(File.symlink?(mine) ? File.readlink(mine) : mine, place)
      else
        File.symlink(File.symlink?(theirs) ? File.readlink(theirs) : File.join(link, name), place)
      end
    end
  end

  # Moves +from+ to +to+, joining the folders both have.
  def self.move(from, to)
    if File.directory?(to) && !File.symlink?(to) && File.directory?(from) && !File.symlink?(from)
      Dir.children(from).each { |name| move(File.join(from, name), File.join(to, name)) }
      Dir.rmdir(from)
    else
      FileUtils.rm_rf(to)
      FileUtils.mkdir_p(File.dirname(to))
      File.rename(from, to)
    end
  end

  # A folder's entries, or none where it is missing or unreadable.
  def self.children(dir)
    File.directory?(dir) ? Dir.children(dir) : []
  rescue Errno::EACCES
    []
  end

  # Whether +path+ is there, as a file, a folder, or a link to anything.
  def self.present?(path)
    File.exist?(path) || File.symlink?(path)
  end

  private_class_method :move, :children, :present?

  # Whether a package is missing that this class can bring.
  private def missing?
    return false unless @linux && !@env.key?(VARIABLE) && found?("dpkg-query")

    printed, = Open3.capture3(tool_env, "dpkg-query", "-W", "-f", "${db:Status-Abbrev}\\n", *packages)
    printed.lines.count { |line| line.start_with?("ii") } < packages.size
  end

  private def found?(tool)
    @env.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, tool)) }
  end

  private def tool_env
    { "PATH" => @env.fetch("PATH", ""), "LC_ALL" => "C" }
  end

  # The build for this system as it is, made first if it is not ready.
  private def prepare
    FileUtils.mkdir_p(@home)
    File.open(File.join(@home, "lock"), File::CREAT | File::RDWR) do |lock|
      lock.flock(File::LOCK_EX)
      build = File.join(@home, key)
      make(build) unless File.exist?(File.join(build, "ready"))
      build
    end
  end

  # What the build depends on: the packages, what dpkg has installed, and
  # where the build lives, which its links name.
  private def key
    Digest::SHA256.hexdigest([LAYOUT, @home, *packages, File.binread(@status)].join("\0"))[0, 16]
  end

  private def make(build)
    FileUtils.rm_rf(build)
    wanted = resolve
    @err.puts "linux-env: fetching and unpacking #{wanted.size} packages this system lacks " \
      "(ci.yml's and what they need) into #{build}"
    fetch(wanted.reject { |package| File.exist?(File.join(debs, package.deb)) })
    root = File.join(build, "root")
    FileUtils.mkdir_p(root)
    wanted.each { |package| run("dpkg-deb", "-x", File.join(debs, package.deb), root) }
    self.class.merge_usr(root, host: @host)
    TOPS.each do |top|
      next unless File.directory?(File.join(root, top))

      FileUtils.mkdir_p(File.join(build, "host", top))
      FileUtils.mkdir_p(File.join(build, "farm"))
      self.class.farm(File.join(build, "farm", top), ours: File.join(root, top), host: File.join(@host, top),
        link: File.join(build, "host", top))
    end
    caches(build, root)
    File.write(File.join(build, "ready"), wanted.map(&:spec).join("\n"))
    prune(build, wanted)
  end

  # What apt-get install would install, by apt's simulation, which needs
  # no root.
  private def resolve
    printed, status = Open3.capture2e(tool_env, "apt-get", "--simulate", "--no-install-recommends", "install",
      *packages)
    raise Failure, "apt-get could not resolve ci.yml's packages:\n#{printed}" unless status.success?

    self.class.simulated(printed)
  end

  private def debs
    File.join(@home, "debs")
  end

  # Downloads +wanted+ with apt, which checks each file against the signed
  # package lists, into a folder of its own, and moves them into debs only
  # once apt has finished.
  private def fetch(wanted)
    partial = File.join(debs, "partial")
    FileUtils.rm_rf(partial)
    FileUtils.mkdir_p(partial)
    return if wanted.empty?

    printed, status = Open3.capture2e(tool_env, "apt-get", "download", *wanted.map(&:spec), chdir: partial)
    raise Failure, "apt-get download failed:\n#{printed}" unless status.success?

    wanted.each do |package|
      File.rename(File.join(partial, package.deb), File.join(debs, package.deb))
    rescue Errno::ENOENT
      raise Failure, "apt-get download wrote no #{package.deb}:\n#{printed}"
    end
  ensure
    FileUtils.rm_rf(partial)
  end

  # Makes what the packages' install scripts would have made, under bwrap
  # with the tree writable, so it lands in the tree.
  private def caches(build, root)
    jobs = []
    if File.directory?(File.join(root, "usr/share/glib-2.0/schemas"))
      jobs << ["glib-compile-schemas", "/usr/share/glib-2.0/schemas"]
    end
    Dir.glob(File.join(root, "usr/lib/*/gdk-pixbuf-2.0/2.10.0/loaders")).each do |loaders|
      triplet = loaders.delete_prefix(File.join(root, "usr/lib/")).split("/").first
      jobs << ["/usr/lib/#{triplet}/gdk-pixbuf-2.0/gdk-pixbuf-query-loaders", "--update-cache"]
    end
    jobs.each { |job| run(*bwrap(build, writable: true), *job) }
  end

  # bwrap's arguments to run a command with +build+'s trees over the
  # system's folders, read-only unless +writable+.
  private def bwrap(build, writable: false)
    tops = TOPS.select { |top| File.directory?(File.join(build, "farm", top)) }
    hosts = tops.flat_map { |top| ["--ro-bind", "/#{top}", File.join(build, "host", top)] }
    farms = tops.flat_map { |top| [writable ? "--bind" : "--ro-bind", File.join(build, "farm", top), "/#{top}"] }
    ["bwrap", "--dev-bind", "/", "/", *hosts, *farms, "--setenv", VARIABLE, build]
  end

  # Deletes every build but +build+, and every download +wanted+ lacks.
  private def prune(build, wanted)
    (Dir.children(@home) - ["debs", "lock", File.basename(build)]).each { |name| FileUtils.rm_rf(File.join(@home, name)) }
    (Dir.children(debs) - wanted.map(&:deb)).each { |name| FileUtils.rm_rf(File.join(debs, name)) }
  end

  private def run(*command)
    printed, status = Open3.capture2e(tool_env, *command)
    raise Failure, "#{command.join(' ')} failed:\n#{printed}" unless status.success?
  end
end
