# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "open3"
require "stringio"
require "tmpdir"
require_relative "../../tasks/linux_gate"

# Tests test:linux (Plan 058): the names each checkout's image, container,
# and volumes take, the docker commands it builds from the repository's
# pins, the manifest and snapshot against real git repositories, and the
# run's order and failures against a stand-in docker that logs its
# arguments.
class TestLinuxGate < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  # A docker that logs each call, one line a call, tab between arguments,
  # keeps what docker run reads on its standard input, and does what files
  # beside it say.
  DOCKER = <<~'SH'
    #!/bin/sh
    dir=$(dirname "$0")
    { printf '%s' docker; for a in "$@"; do printf '\t%s' "$a"; done; printf '\n'; } >> "$dir/log"
    status() { cat "$dir/$1-status" 2> /dev/null || echo 0; }
    case "$1 $2" in
      "ps --all") cat "$dir/containers" 2> /dev/null; exit 0 ;;
      "volume ls") cat "$dir/volumes" 2> /dev/null; exit 0 ;;
      "volume create") exit "$(status volume)" ;;
      "volume rm")
        if [ "$3" = "$(cat "$dir/rm-fails" 2> /dev/null)" ]; then echo "volume is in use"; exit 1; fi
        exit 0 ;;
      "image rm") exit 0 ;;
    esac
    case "$1" in
      build) echo "building"; exit "$(status build)" ;;
      run) cat > "$dir/stdin"; echo "the gate's output"; exit "$(status run)" ;;
    esac
  SH

  def setup
    @dir = Dir.mktmpdir("linux-gate")
    @docker = File.join(@dir, "docker")
    File.write(@docker, DOCKER)
    File.chmod(0o755, @docker)
    @out = StringIO.new
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  private def gate(checkout = ROOT) = LinuxGate.new(checkout:, docker: @docker, out: @out)

  private def calls
    path = File.join(@dir, "log")
    File.exist?(path) ? File.readlines(path, chomp: true).map { |line| line.split("\t") } : []
  end

  private def arrange(name, content = "")
    File.write(File.join(@dir, name), content)
  end

  private def git(dir, *args)
    printed, status = Open3.capture2e(*LinuxGate::GIT, *args, chdir: dir)
    assert status.success?, "git #{args.join(' ')}: #{printed}"
    printed
  end

  # A repository at +dir+ holding +files+ (name to content), committed.
  private def repository(dir, files)
    FileUtils.mkdir_p(dir)
    git(dir, "init", "--quiet")
    files.each do |name, content|
      FileUtils.mkdir_p(File.dirname(File.join(dir, name)))
      File.write(File.join(dir, name), content)
    end
    git(dir, "add", "--all")
    git(dir, "commit", "--quiet", "--message", "files")
  end

  # A checkout with a submodule at vendor/sub, a symlink, an executable,
  # a file deleted from the working tree, and an untracked one.
  private def checkout_with_submodule
    checkout = File.join(@dir, "checkout")
    repository(checkout, "README" => "tokra", "bin/run" => "#!/bin/sh\n", "gone" => "x")
    File.chmod(0o755, File.join(checkout, "bin/run"))
    File.symlink("README", File.join(checkout, "LINK"))
    repository(File.join(checkout, "vendor/sub"), "a.rs" => "fn a() {}", "dir/b.rs" => "fn b() {}")
    git(checkout, "add", "LINK", "bin/run", "vendor/sub")
    git(checkout, "commit", "--quiet", "--message", "submodule")
    File.delete(File.join(checkout, "gone"))
    File.write(File.join(checkout, "untracked"), "not CI's")
    File.write(File.join(checkout, "README"), "changed, not committed")
    checkout
  end

  def test_each_name_is_keyed_by_the_hidden_jobs_slug_of_the_checkout
    slug = HiddenJob.slug("/x/tokra")
    one = LinuxGate.new(checkout: "/x/tokra")

    assert_equal "tokra-linux-#{slug}", one.name
    assert_equal "tokra-linux:#{slug}", one.image
    assert_equal({
      "tokra-linux-#{slug}-cargo" => "/home/tokra/.cargo",
      "tokra-linux-#{slug}-gems" => "/home/tokra/gems",
      "tokra-linux-#{slug}-bundle" => "/work/vendor/bundle",
      "tokra-linux-#{slug}-target" => "/work/target",
      "tokra-linux-#{slug}-tmp" => "/work/tmp",
    }, one.volumes)
  end

  def test_two_checkouts_share_no_image_container_or_volume
    one = LinuxGate.new(checkout: "/a/tokra")
    other = LinuxGate.new(checkout: "/b/tokra")

    refute_equal one.name, other.name
    refute_equal one.image, other.image
    assert_empty one.volumes.keys & other.volumes.keys
  end

  def test_the_image_takes_the_pins_ci_reads_from_the_files_ci_reads_them_from
    args = gate.build_args
    mise = File.read(File.join(ROOT, "mise.toml"))

    assert_equal mise[/^rust = "(.*)"$/, 1], args.fetch("RUST_VERSION")
    assert_equal "clippy,rustfmt", args.fetch("RUST_COMPONENTS")
    assert_equal File.read(File.join(ROOT, "Gemfile.lock"))[/BUNDLED WITH\n\s+(\S+)/, 1], args.fetch("BUNDLER_VERSION")
    assert_match(/\Areuse\[charset-normalizer\]==\d+\.\d+\.\d+\z/, args.fetch("REUSE_REQUIREMENT"))
    packages = args.fetch("APT_PACKAGES").split

    assert_includes packages, "libwebkit2gtk-4.1-dev"
    assert_includes packages, "xvfb"
    assert_includes packages, "libayatana-appindicator3-1"
    refute(packages.any? { |word| word.start_with?("-") || word.include?("\\") }, packages.inspect)
  end

  # A checkout holding only the files the pins are read from, with a
  # stand-in ci.yml whose every step differs from the real one's.
  private def stand_in_pins
    checkout = File.join(@dir, "pins")
    FileUtils.mkdir_p(File.join(checkout, ".github/workflows"))
    File.write(File.join(checkout, "mise.toml"), %([tools]\nruby = "4.0.9"\nrust = "1.2.3"\n))
    File.write(File.join(checkout, "Gemfile.lock"), "GEM\n\nBUNDLED WITH\n  9.8.7\n")
    File.write(File.join(checkout, ".github/workflows/ci.yml"), <<~YAML)
      jobs:
        gate:
          steps:
            - uses: #{LinuxGate::RUST_ACTION}@0123abcd # v1
              with:
                toolchain: stable
                components: miri , rust-src
            - name: #{LinuxGate::REUSE_STEP}
              run: python -m pip install "reuse[x]==1.0"
            - name: #{LinuxGate::APT_STEP}
              run: |
                sudo apt-get update
                sudo apt-get install --yes --no-install-recommends \\
                  one two \\
                  three
                sudo apt-get clean
            - name: #{LinuxGate::BUNDLE_STEP}
              run: |
                bundle config set --local deployment true
                bundle install --jobs 2
            - name: #{LinuxGate::GATE_STEP}
              if: runner.os == 'Linux'
              run: xvfb-run -a -- bundle exec rake gate
    YAML
    checkout
  end

  def test_the_pins_and_packages_are_those_ci_yml_and_its_files_name
    assert_equal({
      "RUST_VERSION" => "1.2.3",
      "RUST_COMPONENTS" => "miri,rust-src",
      "APT_PACKAGES" => "one two three",
      "REUSE_REQUIREMENT" => "reuse[x]==1.0",
      "BUNDLER_VERSION" => "9.8.7",
    }, gate(stand_in_pins).build_args)
  end

  def test_the_container_installs_and_runs_as_ci_yml_says
    steps = gate(stand_in_pins).script(%w[test:gui]).split(" && ")

    assert_equal [
      "bundle config set --local deployment true",
      "bundle install --jobs 2",
      "exec xvfb-run -a -- bundle exec rake gate test:gui",
    ], steps.drop(1)
  end

  def test_the_dockerfiles_ruby_is_mise_tomls_and_in_ci_ymls_matrix
    dockerfile = File.read(File.join(LinuxGate::CONTEXT, "Dockerfile"))
    mise = File.read(File.join(ROOT, "mise.toml"))
    ruby = dockerfile[/^ARG RUBY_VERSION=(\S+)$/, 1]
    matrix = YAML.safe_load_file(File.join(ROOT, ".github/workflows/ci.yml")).dig("jobs", "gate", "strategy", "matrix", "ruby")

    assert_equal mise[/^ruby = "(.*)"$/, 1], ruby
    # The image holds one Ruby, so with more in the matrix test:linux
    # runs only one of them: decide which, or build one image for each.
    assert_equal 1, matrix.size, "ci.yml's matrix runs Rubies #{matrix.inspect}, but test:linux runs only #{ruby}"
    matrix.each { |series| assert ruby.start_with?("#{series}."), "#{ruby} is not in ci.yml's #{series} series" }
    assert_match(/^ARG RUBY_SHA256=\h{64}$/, dockerfile)
    # Ubuntu 24.04's python3 is 3.12; a new pin needs another source.
    assert_equal "3.12", mise[/^python = "(.*)"$/, 1]
    assert_match(/^FROM ubuntu:24\.04$/, dockerfile)
    LinuxGate.new(checkout: ROOT).build_args.each_key { |key| assert_match(/^ARG #{key}$/, dockerfile) }
  end

  def test_the_build_sends_only_its_own_folder_and_tags_the_checkouts_image
    command = gate.build_command

    assert_equal [@docker, "build", "--progress", "plain", "--tag", gate.image], command.first(6)
    assert_equal File.join(ROOT, "tasks/linux"), command.last
    assert_equal ["Dockerfile"], Dir.children(command.last)
    assert_equal gate.build_args.map { |key, value| "#{key}=#{value}" }, command.each_cons(2).select { |flag, _| flag == "--build-arg" }.map(&:last)
  end

  def test_each_volume_is_labeled_with_its_checkout
    assert_equal(gate.volumes.keys.map { |volume| [@docker, "volume", "create", "--label", "dev.tokra.checkout=#{ROOT}", volume] },
      gate.volume_commands)
  end

  def test_the_run_mounts_the_checkout_read_only_and_each_volume_where_it_belongs
    command = gate.run_command
    mounts = command.each_cons(2).select { |flag, _| flag == "--mount" }.map(&:last)

    assert_equal [@docker, "run", "--rm", "--interactive", "--init", "--name", gate.name], command.first(7)
    assert_equal "type=bind,source=#{ROOT},target=/src,readonly", mounts.first
    assert_equal(gate.volumes.map { |volume, path| "type=volume,source=#{volume},target=#{path}" }, mounts.drop(1))
    assert_equal %w[CI=true TOKRA_QUIET=1], command.each_cons(2).select { |flag, _| flag == "--env" }.map(&:last)
    assert_equal [gate.image, "bash", "-c", gate.script], command.last(4)
  end

  def test_the_run_refuses_a_path_its_mount_option_cannot_take
    error = assert_raises(LinuxGate::Failure) { LinuxGate.new(checkout: "/a,b/tokra").run_command }

    assert_equal %(/a,b/tokra has "," in its path, which docker run --mount cannot take), error.message
    error = assert_raises(LinuxGate::Failure) { LinuxGate.new(checkout: %(/a"b/tokra)).run_command }

    assert_equal %(/a"b/tokra has "\\"" in its path, which docker run --mount cannot take), error.message
  end

  def test_the_container_snapshots_then_installs_and_runs_as_ci_yml_does
    steps = gate.script.split(" && ")

    assert_match(%r{\Aruby -I/src/tasks -rlinux_gate -e LinuxGate.snapshot}, steps.first)
    assert_equal [
      "bundle config set --local path vendor/bundle",
      "bundle config set --local frozen true",
      "bundle install --jobs 4",
    ], steps[1, 3]
    assert_equal "exec xvfb-run --auto-servernum dbus-run-session -- bundle exec rake", steps.last
    assert_equal 5, steps.size
    assert_equal "exec xvfb-run --auto-servernum dbus-run-session -- bundle exec rake test:gui plugins:test",
      gate.script(%w[test:gui plugins:test]).split(" && ").last
  end

  def test_the_manifest_holds_what_git_tracks_as_the_working_tree_has_it
    checkout = checkout_with_submodule

    assert_equal({ "files" => %w[LINK README bin/run], "submodules" => { "vendor/sub" => %w[a.rs dir/b.rs] } },
      gate(checkout).manifest)
  end

  # A commit hook runs the gate with GIT_INDEX_FILE and the like set for
  # the superproject; git in a submodule must not read that index.
  def test_the_manifest_ignores_the_git_variables_a_hook_passes_down
    checkout = checkout_with_submodule
    hooked = {
"GIT_DIR" => File.join(checkout, ".git"),
"GIT_INDEX_FILE" => File.join(checkout, ".git", "index"),
"GIT_WORK_TREE" => checkout,
}
    saved = hooked.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
    ENV.update(hooked)

    assert_equal({ "files" => %w[LINK README bin/run], "submodules" => { "vendor/sub" => %w[a.rs dir/b.rs] } },
      gate(checkout).manifest)
  ensure
    ENV.update(saved) if saved
  end

  def test_a_submodule_that_is_not_checked_out_fails_the_manifest
    checkout = checkout_with_submodule
    FileUtils.rm_rf(File.join(checkout, "vendor/sub"))
    FileUtils.mkdir_p(File.join(checkout, "vendor/sub"))
    error = assert_raises(LinuxGate::Failure) { gate(checkout).manifest }

    assert_equal "vendor/sub is not checked out, and CI checks it out. Run: git submodule update --init", error.message
  end

  def test_the_snapshot_is_a_repository_listing_what_the_checkout_tracks
    checkout = checkout_with_submodule
    copy = File.join(@dir, "copy")
    LinuxGate.snapshot(JSON.parse(JSON.generate(gate(checkout).manifest)), from: checkout, to: copy)

    assert_equal "LINK\nREADME\nbin/run\nvendor/sub\n", git(copy, "ls-files")
    assert_match(%r{\A160000 \h+ 0\tvendor/sub\n\z}, git(copy, "ls-files", "--stage", "vendor/sub"))
    assert_equal "a.rs\ndir/b.rs\n", git(File.join(copy, "vendor/sub"), "ls-files")
    assert_equal "", git(copy, "status", "--porcelain")
    assert_equal "changed, not committed", File.read(File.join(copy, "README"))
    assert_equal "README", File.readlink(File.join(copy, "LINK"))
    assert File.executable?(File.join(copy, "bin/run"))
    assert_equal File.mtime(File.join(checkout, "vendor/sub/dir/b.rs")), File.mtime(File.join(copy, "vendor/sub/dir/b.rs"))
    refute File.exist?(File.join(copy, "untracked"))
  end

  # A warm volume holds build output the checkout never tracked; a
  # tracked name that reads as a pattern must not commit it.
  def test_the_snapshot_takes_each_path_literally_never_as_a_pattern
    checkout = File.join(@dir, "checkout")
    repository(checkout, "[ab]" => "a file's name")
    copy = File.join(@dir, "copy")
    FileUtils.mkdir_p(copy)
    File.write(File.join(copy, "a"), "build output")
    LinuxGate.snapshot({ "files" => ["[ab]"], "submodules" => {} }, from: checkout, to: copy)

    assert_equal "[ab]\n", git(copy, "ls-files")
  end

  def test_a_file_that_vanishes_while_it_is_copied_fails_the_snapshot
    checkout = File.join(@dir, "checkout")
    repository(checkout, "README" => "tokra")
    error = assert_raises(LinuxGate::Failure) do
      LinuxGate.snapshot({ "files" => %w[README gone], "submodules" => {} }, from: checkout, to: File.join(@dir, "copy"))
    end

    assert_equal "#{checkout}/gone is gone: the checkout changed while test:linux copied it, so run it again", error.message
  end

  def test_a_submodule_not_at_its_recorded_commit_is_copied_as_it_is_and_said_so
    checkout = checkout_with_submodule
    sub = File.join(checkout, "vendor/sub")
    recorded = git(sub, "rev-parse", "HEAD").strip
    File.write(File.join(sub, "c.rs"), "fn c() {}")
    git(sub, "add", "c.rs")
    git(sub, "commit", "--quiet", "--message", "ahead")
    head = git(sub, "rev-parse", "HEAD").strip

    assert_equal %w[a.rs c.rs dir/b.rs], gate(checkout).manifest.dig("submodules", "vendor/sub")
    assert_equal "== test:linux: vendor/sub is at #{head[0, 12]}, not the #{recorded[0, 12]} the checkout records; " \
      "the container gets its working tree, which CI would not (git submodule update)\n", @out.string
  end

  # +checkout+, with this repository's own pin files beside its own.
  private def with_real_pins(checkout)
    ["mise.toml", "Gemfile.lock", ".github/workflows/ci.yml"].each do |pins|
      FileUtils.mkdir_p(File.dirname(File.join(checkout, pins)))
      FileUtils.cp(File.join(ROOT, pins), File.join(checkout, pins))
    end
    checkout
  end

  def test_a_run_builds_creates_the_volumes_and_runs_with_the_manifest_on_its_input
    checkout = with_real_pins(checkout_with_submodule)
    gate(checkout).run(%w[test:gui])

    assert_equal [
      ["docker", "ps", "--all", "--quiet", "--filter", "name=^#{gate(checkout).name}$"],
      ["docker", *gate(checkout).build_command.drop(1)],
      *gate(checkout).volume_commands.map { |command| ["docker", *command.drop(1)] },
      ["docker", *gate(checkout).run_command(%w[test:gui]).drop(1)],
    ], calls
    assert_equal gate(checkout).manifest, JSON.parse(File.read(File.join(@dir, "stdin")))
    assert_equal "== test:linux: build #{gate(checkout).image}\nbuilding\n" \
      "== test:linux: test:gui in #{gate(checkout).name}\nthe gate's output\n", @out.string
  end

  def test_a_clean_run_empties_the_build_volumes_before_it_creates_them
    checkout = with_real_pins(checkout_with_submodule)
    gate(checkout).run([], clean: true)
    name = gate(checkout).name

    assert_equal [["docker", "volume", "rm", "--force", "#{name}-target"], ["docker", "volume", "rm", "--force", "#{name}-tmp"]],
      calls.select { |call| call[1, 2] == %w[volume rm] }
    assert_operator calls.index { |call| call[1] == "build" }, :<, calls.index { |call| call[1, 2] == %w[volume rm] }
    assert_operator calls.rindex { |call| call[1, 2] == %w[volume rm] }, :<, calls.index { |call| call[1, 2] == %w[volume create] }
  end

  def test_a_run_that_is_not_clean_keeps_the_build_volumes
    gate(with_real_pins(checkout_with_submodule)).run

    assert_empty(calls.select { |call| call[1, 2] == %w[volume rm] })
  end

  def test_a_run_refuses_while_the_checkouts_container_exists
    arrange("containers", "4f2c\n")
    error = assert_raises(LinuxGate::Failure) { gate.run }

    assert_match(/container #{gate.name} exists, so another test:linux of this checkout is running/, error.message)
    assert_equal 1, calls.size
  end

  def test_a_failing_step_fails_the_run_by_name
    arrange("build-status", "3")

    assert_equal "build #{gate.image} failed (exit 3)", assert_raises(LinuxGate::Failure) { gate.run }.message

    arrange("build-status", "0")
    arrange("run-status", "1")

    assert_equal "the gate in #{gate.name} failed (exit 1)", assert_raises(LinuxGate::Failure) { gate.run }.message
  end

  def test_prune_removes_only_the_volumes_and_images_of_checkouts_that_are_gone
    gone = File.join(@dir, "gone")
    kept = LinuxGate.new(checkout: @dir)
    lost = LinuxGate.new(checkout: gone)
    listed = kept.volumes.keys.map { |volume| "#{volume}\t#{@dir}" } + lost.volumes.keys.map { |volume| "#{volume}\t#{gone}" }
    arrange("volumes", listed.join("\n"))

    assert_equal lost.volumes.keys, gate.prune
    assert_equal(lost.volumes.keys.map { |volume| ["docker", "volume", "rm", volume] },
      calls.select { |call| call[1, 2] == %w[volume rm] })
    assert_equal [["docker", "image", "rm", lost.image]], calls.select { |call| call[1, 2] == %w[image rm] }
    assert_equal(lost.volumes.keys.map { |volume| "== test:linux:prune: removed #{volume}\n" }.join, @out.string)
  end

  def test_prune_goes_on_past_a_volume_it_cannot_remove_and_then_fails_naming_it
    lost = LinuxGate.new(checkout: File.join(@dir, "gone"))
    arrange("volumes", lost.volumes.keys.map { |volume| "#{volume}\t#{File.join(@dir, 'gone')}" }.join("\n"))
    stuck = lost.volumes.keys[1]
    arrange("rm-fails", stuck)
    error = assert_raises(LinuxGate::Failure) { gate.prune }

    assert_equal "could not remove #{stuck} (volume is in use)", error.message
    assert_equal(lost.volumes.keys.map { |volume| ["docker", "volume", "rm", volume] },
      calls.select { |call| call[1, 2] == %w[volume rm] })
    assert_equal((lost.volumes.keys - [stuck]).map { |volume| "== test:linux:prune: removed #{volume}\n" }.join, @out.string)
  end
end
