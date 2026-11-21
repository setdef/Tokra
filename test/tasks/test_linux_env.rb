# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "fileutils"
require "stringio"
require "tmpdir"
require_relative "../../tasks/linux_env"

# Tests bin/linux-env (Plan 068): when it runs a command unchanged, and how
# it brings ci.yml's packages without root otherwise. Each test runs
# LinuxEnv in folders of its own, with stand-ins for dpkg-query, apt-get,
# dpkg-deb, and bwrap that log their arguments and do what files beside
# them say, so it runs on any system and touches no network.
class TestLinuxEnv < Minitest::Test
  # Logs each call, one line a call, tab between arguments, and its folder.
  LOG = <<~'SH'
    dir=$(dirname "$0")
    { printf '%s' "$(basename "$0")"; for a in "$@"; do printf '\t%s' "$a"; done; printf '\n'; } >> "$dir/log"
  SH

  # Says every package is installed when the file "installed" is there.
  DPKG_QUERY = <<~SH
    shift 3
    for p in "$@"; do
      if [ -e "$dir/installed" ]; then echo "ii "; else echo "un "; fi
    done
  SH

  # Prints the file "simulation"; downloads a file for each name=version,
  # named as apt names it, unless "download-fails" says what to print.
  APT_GET = <<~SH
    case "$1" in
      --simulate) cat "$dir/simulation" ;;
      download)
        if [ -e "$dir/download-fails" ]; then cat "$dir/download-fails"; exit 100; fi
        shift
        for spec in "$@"; do
          name=${spec%%=*}; version=$(printf '%s' "${spec#*=}" | sed 's/:/%3a/')
          echo "$name" > "${name}_${version}_amd64.deb"
        done ;;
    esac
  SH

  # Unpacks DEB into DIR as usr/share/NAME/NAME, and the paths the file
  # "files.NAME" lists, each a line.
  DPKG_DEB = <<~SH
    name=$(cat "$2")
    mkdir -p "$3/usr/share/$name"
    echo "$name" > "$3/usr/share/$name/$name"
    if [ -e "$dir/files.$name" ]; then
      while read -r path; do mkdir -p "$3/$(dirname "$path")"; echo "$name" > "$3/$path"; done < "$dir/files.$name"
    fi
  SH

  SIMULATION = <<~TEXT
    NOTE: This is only a simulation!
          apt-get needs root privileges for real execution.
    Reading package lists...
    The following NEW packages will be installed:
      libfoo-dev libfoo1
    Inst libfoo1 (1.2-3 Ubuntu:24.04/noble [amd64])
    Inst libbar2 [2.0-1] (2.0-2 Ubuntu:24.04/noble-updates, Ubuntu:24.04/noble-security [amd64])
    Inst libfoo-dev (1:1.2-3 Ubuntu:24.04/noble [amd64])
    Conf libfoo1 (1.2-3 Ubuntu:24.04/noble [amd64])
    Conf libfoo-dev (1:1.2-3 Ubuntu:24.04/noble [amd64])
  TEXT

  def setup
    skip "the stand-ins are POSIX shell scripts" if Gem.win_platform?

    @dir = File.realpath(Dir.mktmpdir("linux_env"))
    @bin = File.join(@dir, "bin")
    Dir.mkdir(@bin)
    { "dpkg-query" => DPKG_QUERY, "apt-get" => APT_GET, "dpkg-deb" => DPKG_DEB, "bwrap" => "" }.each do |name, body|
      stand_in(name, body)
    end
    File.write(File.join(@bin, "simulation"), SIMULATION)
    @checkout = File.join(@dir, "checkout")
    Dir.mkdir(@checkout)
    @status = File.join(@dir, "status")
    File.write(@status, "Package: one\n")
    @host = File.join(@dir, "host")
    FileUtils.mkdir_p(File.join(@host, "usr/share/host"))
    File.write(File.join(@host, "usr/share/host/file"), "host")
  end

  def teardown
    FileUtils.rm_rf(@dir) if @dir
  end

  private def stand_in(name, body)
    path = File.join(@bin, name)
    File.write(path, "#!/bin/sh\n#{LOG}#{body}")
    File.chmod(0o755, path)
  end

  private def linux_env(linux: true, env: {})
    LinuxEnv.new(checkout: @checkout, packages: %w[libfoo-dev xdotool], linux:, status: @status, host: @host,
      env: { "PATH" => "#{@bin}#{File::PATH_SEPARATOR}/usr/bin#{File::PATH_SEPARATOR}/bin" }.merge(env),
      err: StringIO.new)
  end

  # Each stand-in's calls, by name, each an Array of its arguments.
  private def calls(name)
    log = File.join(@bin, "log")
    lines = File.exist?(log) ? File.readlines(log, chomp: true) : []
    lines.map { |line| line.split("\t") }.select { |call| call.first == name }.map { |call| call.drop(1) }
  end

  private def home = File.join(@checkout, "tmp/linux-env")

  # The one build there is, by its folder.
  private def build
    builds = Dir.children(home) - %w[debs lock]

    assert_equal 1, builds.size, builds.inspect
    File.join(home, builds.first)
  end

  private def wrapped(build, *command)
    [
      "bwrap",
      "--dev-bind",
      "/",
      "/",
      "--ro-bind",
      "/usr",
      "#{build}/host/usr",
      "--ro-bind",
      "#{build}/farm/usr",
      "/usr",
      "--setenv",
      "TOKRA_LINUX_ENV",
      build,
      *command,
]
  end

  def test_the_packages_are_those_ci_installs
    root = File.expand_path("../..", __dir__)
    packages = LinuxEnv.new(checkout: root).packages

    assert_includes packages, "libwebkit2gtk-4.1-dev"
    assert_includes packages, "xdotool"
    refute_includes packages, "--no-install-recommends"
  end

  def test_off_linux_it_runs_the_command_unchanged_and_asks_nothing
    assert_equal %w[echo hi], linux_env(linux: false).command(%w[echo hi])
    assert_empty calls("dpkg-query")
  end

  def test_without_dpkg_query_it_runs_the_command_unchanged
    File.delete(File.join(@bin, "dpkg-query"))

    # Only the stand-ins, since a Debian system has the real dpkg-query.
    assert_equal %w[echo hi], linux_env(env: { "PATH" => @bin }).command(%w[echo hi])
    assert_empty calls("apt-get")
  end

  # As on CI, and wherever ci.yml's apt-get install has run.
  def test_with_every_package_installed_it_runs_the_command_unchanged
    File.write(File.join(@bin, "installed"), "")

    assert_equal %w[echo hi], linux_env.command(%w[echo hi])
    assert_equal [["-W", "-f", "${db:Status-Abbrev}\\n", "libfoo-dev", "xdotool"]], calls("dpkg-query")
    assert_empty calls("apt-get")
    refute_path_exists home
  end

  def test_under_itself_it_runs_the_command_unchanged
    assert_equal %w[echo hi], linux_env(env: { "TOKRA_LINUX_ENV" => "/somewhere" }).command(%w[echo hi])
    assert_empty calls("dpkg-query")
  end

  def test_with_packages_missing_it_fetches_and_unpacks_what_apt_would_install_and_wraps_the_command
    command = linux_env.command(%w[echo hi])

    assert_equal [
      %w[--simulate --no-install-recommends install libfoo-dev xdotool],
      %w[download libfoo1=1.2-3 libbar2=2.0-2 libfoo-dev=1:1.2-3],
], calls("apt-get")
    debs = File.join(home, "debs")

    assert_equal %w[libbar2_2.0-2_amd64.deb libfoo-dev_1%3a1.2-3_amd64.deb libfoo1_1.2-3_amd64.deb],
      Dir.children(debs).sort
    assert_equal %w[libfoo1_1.2-3_amd64.deb libbar2_2.0-2_amd64.deb libfoo-dev_1%3a1.2-3_amd64.deb],
      calls("dpkg-deb").map { |call| File.basename(call[1]) }
    assert_equal wrapped(build, "echo", "hi"), command
    assert_equal "libfoo1\n", File.read(File.join(build, "farm/usr/share/libfoo1/libfoo1"))
    assert_equal File.join(build, "host/usr/share/host"), File.readlink(File.join(build, "farm/usr/share/host"))
  end

  def test_packages_that_ship_etc_get_etc_bound_too
    File.write(File.join(@bin, "files.libfoo1"), "etc/xdg/foo/foorc\n")
    FileUtils.mkdir_p(File.join(@host, "etc"))
    command = linux_env.command(%w[true])

    assert_equal [
      "bwrap",
      "--dev-bind",
      "/",
      "/",
      "--ro-bind",
      "/usr",
      "#{build}/host/usr",
      "--ro-bind",
      "/etc",
      "#{build}/host/etc",
      "--ro-bind",
      "#{build}/farm/usr",
      "/usr",
      "--ro-bind",
      "#{build}/farm/etc",
      "/etc",
      "--setenv",
      "TOKRA_LINUX_ENV",
      build,
      "true",
], command
  end

  def test_a_second_run_reuses_the_build_and_fetches_and_unpacks_nothing
    first = linux_env.command(%w[true])
    File.delete(File.join(@bin, "log"))
    second = linux_env.command(%w[true])

    assert_equal first, second
    assert_empty calls("apt-get")
    assert_empty calls("dpkg-deb")
  end

  # Installing or upgrading a system package changes what is missing.
  def test_a_changed_status_builds_again_downloads_only_what_is_new_and_removes_the_old
    linux_env.command(%w[true])
    old = build
    File.write(@status, "Package: two\n")
    File.write(File.join(@bin, "simulation"), "Inst libfoo1 (1.2-3 Ubuntu:24.04/noble [amd64])\n" \
      "Inst libnew1 (5 Ubuntu:24.04/noble [amd64])\n")
    File.delete(File.join(@bin, "log"))
    command = linux_env.command(%w[true])

    assert_equal [%w[download libnew1=5]], calls("apt-get").drop(1)
    refute_equal old, build
    refute_path_exists old
    assert_equal %w[libfoo1_1.2-3_amd64.deb libnew1_5_amd64.deb], Dir.children(File.join(home, "debs")).sort
    assert_equal wrapped(build, "true"), command
  end

  def test_a_failed_download_keeps_no_file_and_says_what_apt_said
    File.write(File.join(@bin, "download-fails"), "E: Failed to fetch libfoo1 404 Not Found")
    error = assert_raises(LinuxEnv::Failure) { linux_env.command(%w[true]) }

    assert_includes error.message, "404 Not Found"
    assert_empty Dir.children(File.join(home, "debs"))
  end

  def test_a_failed_simulation_says_what_apt_said
    stand_in("apt-get", "echo 'E: Package xdotool has no installation candidate'; exit 100")
    error = assert_raises(LinuxEnv::Failure) { linux_env.command(%w[true]) }

    assert_includes error.message, "has no installation candidate"
  end

  def test_a_build_cut_short_is_built_again
    linux_env.command(%w[true])
    File.delete(File.join(build, "ready"))
    File.delete(File.join(@bin, "log"))
    command = linux_env.command(%w[true])

    assert_equal 3, calls("dpkg-deb").size
    assert_path_exists File.join(build, "ready")
    assert_equal wrapped(build, "true"), command
  end

  def test_settings_schemas_and_pixbuf_loaders_are_compiled_in_the_writable_tree
    File.write(File.join(@bin, "files.libfoo1"), "usr/share/glib-2.0/schemas/org.foo.gschema.xml\n" \
      "usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0/2.10.0/loaders/libpng.so\n" \
      "usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0/gdk-pixbuf-query-loaders\n")
    linux_env.command(%w[true])
    writable = [
      "--dev-bind",
      "/",
      "/",
      "--ro-bind",
      "/usr",
      "#{build}/host/usr",
      "--bind",
      "#{build}/farm/usr",
      "/usr",
      "--setenv",
      "TOKRA_LINUX_ENV",
      build,
]

    assert_equal [
      [*writable, "glib-compile-schemas", "/usr/share/glib-2.0/schemas"],
      [*writable, "/usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0/gdk-pixbuf-query-loaders", "--update-cache"],
],
      calls("bwrap")
  end

  def test_a_cache_that_fails_to_build_says_what_its_tool_said
    File.write(File.join(@bin, "files.libfoo1"), "usr/share/glib-2.0/schemas/org.foo.gschema.xml\n")
    stand_in("bwrap", "echo 'bad schema'; exit 1")
    error = assert_raises(LinuxEnv::Failure) { linux_env.command(%w[true]) }

    assert_includes error.message, "bad schema"
    refute_path_exists File.join(build, "ready")
  end

  def test_no_cache_is_made_where_no_package_has_its_files
    linux_env.command(%w[true])

    assert_empty calls("bwrap")
  end

  def test_the_simulations_inst_lines_upgrades_among_them_are_the_packages
    assert_equal [
      LinuxEnv::Package.new(name: "libfoo1", version: "1.2-3", arch: "amd64"),
      LinuxEnv::Package.new(name: "libbar2", version: "2.0-2", arch: "amd64"),
      LinuxEnv::Package.new(name: "libfoo-dev", version: "1:1.2-3", arch: "amd64"),
],
      LinuxEnv.simulated(SIMULATION)
  end

  def test_a_package_names_the_file_apt_writes_for_it
    assert_equal "libfoo-dev_1%3a1.2-3_amd64.deb", LinuxEnv::Package.new(name: "libfoo-dev", version: "1:1.2-3", arch: "amd64").deb
    assert_equal "fonts-x_2_all.deb", LinuxEnv::Package.new(name: "fonts-x:all", version: "2", arch: "all").deb
    assert_equal "libfoo-dev=1:1.2-3", LinuxEnv::Package.new(name: "libfoo-dev", version: "1:1.2-3", arch: "amd64").spec
  end

  # A merged /usr system's dpkg puts what a package ships in /lib into
  # /usr/lib, through the link.
  def test_what_a_package_ships_in_lib_moves_into_usr
    root = File.join(@dir, "root")
    FileUtils.mkdir_p(File.join(root, "lib/x86_64-linux-gnu"))
    FileUtils.mkdir_p(File.join(root, "usr/lib/x86_64-linux-gnu"))
    File.write(File.join(root, "lib/x86_64-linux-gnu/liba.so.1"), "a")
    File.write(File.join(root, "usr/lib/x86_64-linux-gnu/libb.so.1"), "b")
    FileUtils.mkdir_p(File.join(root, "sbin"))
    File.write(File.join(root, "sbin/tool"), "t")
    FileUtils.mkdir_p(File.join(@host, "usr/lib"))
    FileUtils.mkdir_p(File.join(@host, "usr/sbin"))
    File.symlink("usr/lib", File.join(@host, "lib"))
    File.symlink("usr/sbin", File.join(@host, "sbin"))
    LinuxEnv.merge_usr(root, host: @host)

    assert_equal %w[usr], Dir.children(root)
    assert_equal %w[liba.so.1 libb.so.1], Dir.children(File.join(root, "usr/lib/x86_64-linux-gnu")).sort
    assert_equal "t", File.read(File.join(root, "usr/sbin/tool"))
  end

  def test_where_the_system_keeps_lib_apart_it_stays_apart
    root = File.join(@dir, "root")
    FileUtils.mkdir_p(File.join(root, "lib"))
    FileUtils.mkdir_p(File.join(@host, "lib"))
    LinuxEnv.merge_usr(root, host: @host)

    assert_equal %w[lib], Dir.children(root)
  end

  def test_the_tree_of_links_joins_folders_lets_the_unpacked_file_win_and_copies_links
    ours = File.join(@dir, "ours")
    host = File.join(@dir, "hostusr")
    FileUtils.mkdir_p(File.join(ours, "lib/gnu/webkit"))
    FileUtils.mkdir_p(File.join(host, "lib/gnu"))
    FileUtils.mkdir_p(File.join(host, "local/bin"))
    File.write(File.join(ours, "lib/gnu/webkit/WebProcess"), "ours")
    File.write(File.join(ours, "lib/gnu/libfoo.so.1"), "ours")
    File.symlink("libfoo.so.1", File.join(ours, "lib/gnu/libfoo.so"))
    File.write(File.join(host, "lib/gnu/libfoo.so.1"), "host")
    File.write(File.join(host, "lib/gnu/libc.so.6"), "host")
    File.symlink("../../run/x", File.join(host, "lib/gnu/up"))
    farm = File.join(@dir, "farm")
    LinuxEnv.farm(farm, ours:, host:, link: "/bound/usr")

    assert_equal %w[lib local], Dir.children(farm).sort
    assert_equal "/bound/usr/local", File.readlink(File.join(farm, "local"))
    refute File.symlink?(File.join(farm, "lib/gnu"))
    assert_equal %w[libc.so.6 libfoo.so libfoo.so.1 up webkit], Dir.children(File.join(farm, "lib/gnu")).sort
    assert_equal File.join(ours, "lib/gnu/webkit"), File.readlink(File.join(farm, "lib/gnu/webkit"))
    assert_equal File.join(ours, "lib/gnu/libfoo.so.1"), File.readlink(File.join(farm, "lib/gnu/libfoo.so.1"))
    assert_equal "libfoo.so.1", File.readlink(File.join(farm, "lib/gnu/libfoo.so"))
    assert_equal "/bound/usr/lib/gnu/libc.so.6", File.readlink(File.join(farm, "lib/gnu/libc.so.6"))
    assert_equal "../../run/x", File.readlink(File.join(farm, "lib/gnu/up"))
  end
end
