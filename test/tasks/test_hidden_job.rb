# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "stringio"
require "tmpdir"
require_relative "../../tasks/hidden_job"

# Tests test:hidden's job (Plan 056) against stand-ins for the hidden
# session's scripts: each logs its arguments, one line a call, tab
# between them, and does what files beside it say.
class TestHiddenJob < Minitest::Test
  TOOLS = %w[
    --env
    PATH=/Users/Shared/hidden-tools/mise/bin:/usr/bin
    --env
    RUSTUP_HOME=/Users/Shared/hidden-tools/rustup
    --env
    RUSTUP_TOOLCHAIN=1.99.1
  ].freeze

  # The two tracked files stage would refuse, which the maintainer
  # approved.
  ALLOWS = %w[
    --allow
    vendor/tauri/crates/tauri-utils/src/tokens.rs
    --allow
    vendor/tauri/crates/tauri/test/updater/fixture/*
  ].freeze

  # What the job adds to toolchain-env's options, and runs.
  JOB = %w[
    --env
    CARGO_HOME=/Users/tokratest/.cargo
    --env
    TOKRA_QUIET=1
    --env
    TOKRA_REAL_WINDOWS=local
    --env
    TOKRA_HIDDEN_JOB=1
    --
    bundle
    exec
    rake
    test:keyboard
    test:real_windows
  ].freeze

  PREAMBLE = <<~'SH'
    #!/bin/sh
    dir=$(dirname "$0")
    { printf '%s' "$(basename "$0")"; for a in "$@"; do printf '\t%s' "$a"; done; printf '\n'; } >> "$dir/log"
    status() { cat "$dir/$1-status" 2> /dev/null || echo 0; }
  SH

  SCRIPTS = {
    "hidden-run" => <<~SH,
      for a in "$@"; do last=$a; done
      case " $* " in
        *" --ping "*) echo "hidden session answering: tokratest"; exit "$(status ping)" ;;
        *" /bin/rm "*) exit 0 ;;
        *"/mirror "*)
          echo "mirror: 3 files tracked"
          [ -e "$dir/mirror-silent" ] || echo "mirror: $last/tokra"
          exit "$(status mirror)" ;;
      esac
      printf 'first'
      while [ -e "$dir/hold" ]; do sleep 0.01; done
      echo " and the tests' output"
      echo "the tests' errors" >&2
      [ -e "$dir/killed" ] && kill -TERM $$
      exit "$(status job)"
    SH
    "stage" => <<~SH,
      to=
      while [ $# -gt 0 ]; do [ "$1" = --to ] && to=$2; shift; done
      echo "stage: publishing, as --allow says, names that look like credentials:"
      [ -e "$dir/stage-silent" ] || echo "stage: $to/tokra"
      exit "$(status stage)"
    SH
    "toolchain-env" => <<~'SH',
      if [ "$(status toolchain)" != 0 ]; then
        echo "toolchain-env: tokra's tools are not all installed" >&2; exit 1
      fi
      printf '%s\n' --env PATH=/Users/Shared/hidden-tools/mise/bin:/usr/bin \
        --env RUSTUP_HOME=/Users/Shared/hidden-tools/rustup --env RUSTUP_TOOLCHAIN=1.99.1
      cat "$dir/tools-extra" 2> /dev/null
      exit 0
    SH
    "hidden-tools-install" => <<~SH,
      case " $* " in
        *" --check "*) if [ -e "$dir/missing" ]; then echo "missing: gems"; exit 1; fi; exit 0 ;;
      esac
      [ -e "$dir/install-broken" ] || rm -f "$dir/missing"
      exit "$(status install)"
    SH
  }.freeze

  def setup
    skip "the hidden session's scripts are POSIX shell" if Gem.win_platform?
    @scripts = Dir.mktmpdir("hidden_session")
    @checkout = Dir.mktmpdir("checkout")
    @sources = Dir.mktmpdir("hidden-src")
    SCRIPTS.each do |name, body|
      path = File.join(@scripts, name)
      File.write(path, PREAMBLE + body)
      File.chmod(0o755, path)
    end
    @out = StringIO.new
    slug = HiddenJob.slug(@checkout)
    @source = "#{@sources}/tokra-#{slug}"
    @staged = "#{@source}/tokra"
    @mirror = "/Users/tokratest/tokra-mirror-#{slug}"
  end

  def teardown
    [@scripts, @checkout, @sources].compact.each { |dir| FileUtils.rm_rf(dir) }
  end

  private def job(plugins: true, checkout: @checkout)
    HiddenJob.new(checkout:, scripts: @scripts, out: @out, plugins:, sources: @sources,
      tools_lock: File.join(@scripts, "tools.lock"))
  end

  private def calls
    path = File.join(@scripts, "log")
    File.exist?(path) ? File.readlines(path, chomp: true).map { |line| line.split("\t") } : []
  end

  private def arrange(name, content = "")
    File.write(File.join(@scripts, name), content)
  end

  private def failure(&)
    assert_raises(HiddenJob::Failure, &).message
  end

  # Waits until the output says +text+, failing if the job ends first, or
  # if a minute passes without it, which on any load means it never will.
  private def until_said(text, thread)
    give_up = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 60
    sleep 0.01 until @out.string.include?(text) || !thread.alive? ||
        Process.clock_gettime(Process::CLOCK_MONOTONIC) > give_up

    assert_includes @out.string, text
  end

  # Holds the lock at +path+ while the block runs.
  private def holding(path)
    FileUtils.mkdir_p(File.dirname(path))
    File.open(path, File::RDWR | File::CREAT) do |lock|
      lock.flock(File::LOCK_EX)
      yield
    end
  end

  def test_a_run_pings_stages_checks_mirrors_and_runs_the_tests_in_that_order
    job.run

    assert_equal [
      %w[hidden-run --account tokratest --ping],
      ["stage", "--to", @source, *ALLOWS, "tokra", @checkout],
      ["hidden-tools-install", "--check", "--staged", @staged, "tokra"],
      ["toolchain-env", "tokra", @staged],
      %w[hidden-run --account tokratest --merge --timeout 1800 -- /Users/Shared/hidden-session/mirror]
        .push(@staged, @mirror),
      %w[hidden-run --account tokratest --merge --timeout 5400 --min-free-gb 20 --cwd]
        .push("#{@mirror}/tokra", *TOOLS, *JOB, "test:real_windows:plugins"),
    ], calls
  end

  def test_each_checkout_has_a_copy_and_a_mirror_of_its_own
    one = job.place
    other = job(checkout: "#{@checkout}-other").place

    assert_equal HiddenJob::Place.new(source: @source, mirror: @mirror), one
    refute_equal one.source, other.source
    refute_equal one.mirror, other.mirror
  end

  def test_a_slug_names_the_folder_and_digests_the_whole_path
    assert_equal "agent-a7e-#{Digest::SHA256.hexdigest('/x/Agent.A7E')[0, 8]}", HiddenJob.slug("/x/Agent.A7E")
    refute_equal HiddenJob.slug("/a/tokra"), HiddenJob.slug("/b/tokra")
  end

  def test_missing_tools_install_then_check_again
    arrange("missing")
    job.run

    installs = calls.select { |call| call.first == "hidden-tools-install" }

    assert_equal [
      ["hidden-tools-install", "--check", "--staged", @staged, "tokra"],
      ["hidden-tools-install", "--staged", @staged, "tokra"],
      ["hidden-tools-install", "--check", "--staged", @staged, "tokra"],
    ], installs
  end

  def test_tools_still_missing_after_the_install_fail_the_job
    arrange("missing")
    arrange("install-broken")

    assert_equal "hidden-tools-install --check, after installing: failed (exit 1)", failure { job.run }
    refute(calls.any? { |call| call.include?("test:keyboard") })
  end

  def test_a_failed_install_fails_the_job
    arrange("missing")
    arrange("install-status", "1")

    assert_equal "hidden-tools-install: failed (exit 1)", failure { job.run }
  end

  def test_installs_of_two_checkouts_take_turns
    arrange("missing")
    holding(File.join(@scripts, "tools.lock")) do
      @thread = Thread.new { job.run }
      until_said("waiting for another checkout's hidden-tools-install", @thread)

      refute(calls.any? { |call| call.first == "hidden-tools-install" })
    end
    @thread.join

    assert_equal 3, calls.count { |call| call.first == "hidden-tools-install" }
  end

  def test_gates_of_one_checkout_take_turns
    holding(File.join(@checkout, "tmp/hidden-job.lock")) do
      @thread = Thread.new { job.run }
      until_said("waiting for another hidden gate of this checkout", @thread)

      assert_equal [%w[hidden-run --account tokratest --ping]], calls
    end
    @thread.join

    assert_equal "test:real_windows:plugins", calls.last.last
  end

  def test_output_streams_as_it_comes_not_a_line_at_a_time
    arrange("hold")
    thread = Thread.new { job.run }
    until_said("== test:hidden: the real-window tests in tokratest\nfirst", thread)
    File.delete(File.join(@scripts, "hold"))
    thread.join

    assert_includes @out.string, "first and the tests' output\n"
    assert_includes @out.string, "the tests' errors\n"
    assert_includes @out.string, "hidden session answering: tokratest\n"
  end

  def test_with_the_plugins_their_real_window_tests_run_too
    job.run

    assert_equal [*JOB, "test:real_windows:plugins"], calls.last.last(JOB.size + 1)
    refute_includes @out.string, "did NOT run"
  end

  def test_without_the_plugins_it_says_their_real_window_tests_did_not_run
    job(plugins: false).run

    assert_equal JOB, calls.last.last(JOB.size)
    assert_match(/plugins' real-window tests did NOT run.*TOKRA_REAL_WINDOWS=local rake test:real_windows:plugins/,
      @out.string.lines.last)
  end

  def test_the_job_never_runs_bundle_install_where_the_gems_are_read_only
    job.run

    refute(calls.any? { |call| call.each_cons(2).include?(%w[bundle install]) })
  end

  def test_the_job_never_names_a_desktop_input_lock_of_its_own
    arrange("tools-extra", "--env\nDESKTOP_INPUT_LOCK=/tmp/desktop-input.lock\n")
    job.run

    refute(calls.last.any? { |arg| arg.include?("DESKTOP_INPUT_LOCK") })
    assert_equal TOOLS, calls.last[calls.last.index("--cwd") + 2, TOOLS.size]
  end

  def test_a_path_in_the_maintainers_home_is_never_handed_to_the_account
    arrange("tools-extra", "--env\nLOTA_HOME=#{Dir.home}/Developer/rove_2d\n")

    assert_match(/LOTA_HOME=.* names #{Regexp.escape(Dir.home)}, which tokratest cannot open/, failure { job.run })
    refute(calls.any? { |call| call.include?("/Users/Shared/hidden-session/mirror") })
  end

  def test_a_runner_that_does_not_answer_fails_and_nothing_runs
    arrange("ping-status", "69")

    assert_match(/tokratest's hidden session is not answering .*TOKRA_REAL_WINDOWS=local/, failure { job.run })
    assert_equal [%w[hidden-run --account tokratest --ping]], calls
  end

  def test_without_hidden_run_it_fails_and_says_how_to_run_here
    File.delete(File.join(@scripts, "hidden-run"))

    assert_match(%r{no hidden-run at #{@scripts}/hidden-run.*TOKRA_REAL_WINDOWS=local}, failure { job.run })
    assert_empty calls
  end

  def test_each_missing_script_fails_by_name
    %w[stage hidden-tools-install toolchain-env].each do |name|
      path = File.join(@scripts, name)
      File.rename(path, "#{path}.away")

      assert_includes failure { job.run }, "no #{name} at #{path}"
      File.rename("#{path}.away", path)
    end
  end

  def test_a_job_the_runner_never_took_is_no_pass
    arrange("job-status", "69")

    assert_match(/the real-window tests in tokratest: the runner never took the job .* this is no pass/,
      failure { job.run })
  end

  def test_each_of_hidden_runs_statuses_says_what_it_means
    { "70" => "refused", "75" => "too little memory", "124" => "past its timeout", "130" => "interrupted" }
      .each do |code, meaning|
        arrange("job-status", code)

        assert_includes failure { job.run }, meaning
      end
  end

  def test_a_killed_step_names_its_signal
    arrange("killed")

    assert_equal "the real-window tests in tokratest: killed by SIGTERM", failure { job.run }
  end

  def test_failing_tests_fail_with_their_status
    arrange("job-status", "1")

    assert_equal "the real-window tests in tokratest: failed (exit 1)", failure { job.run }
    refute_includes @out.string, "did NOT run"
  end

  def test_a_failed_mirror_runs_no_tests
    arrange("mirror-status", "1")

    assert_equal "mirror: failed (exit 1)", failure { job.run }
    refute(calls.any? { |call| call.include?("test:keyboard") })
  end

  def test_a_stage_that_does_not_say_where_fails
    arrange("stage-silent")

    assert_equal "stage did not say where it published #{@checkout}", failure { job.run }
  end

  def test_a_mirror_that_does_not_say_where_fails
    arrange("mirror-silent")

    assert_equal "mirror did not say where it copied #{@staged}", failure { job.run }
  end

  def test_tools_toolchain_env_finds_missing_stop_the_job
    arrange("toolchain-status", "1")

    assert_equal "toolchain-env tokra failed (its reason is above)", failure { job.run }
    assert_includes @out.string, "toolchain-env: tokra's tools are not all installed\n"
    refute(calls.any? { |call| call.include?("test:keyboard") })
  end

  def test_prune_removes_the_copy_and_mirror_of_each_checkout_that_is_gone
    { "tokra-gone-1" => "/nowhere/gone", "tokra-here-2" => @checkout, "tokra-unknown-3" => nil }
      .each do |name, checkout|
        FileUtils.mkdir_p(File.join(@sources, name))
        File.write(File.join(@sources, name, ".stage"), "run=x\ncheckout=#{checkout}\nhead=y\n") if checkout
      end

    assert_equal ["#{@sources}/tokra-gone-1"], job.prune
    assert_equal %w[tokra-here-2 tokra-unknown-3], Dir.children(@sources).sort
    assert_equal [%w[hidden-run --account tokratest --merge -- /bin/rm -rf /Users/tokratest/tokra-mirror-gone-1]],
      calls
  end
end
