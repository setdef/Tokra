# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Fixture for restart_test.rb: an app that restarts itself three ways,
# then exits (Plan 039). It loads no page, so it runs on Windows too.
#
# Each run counts the runs before it in the --log file and appends one JSON
# line per thing it saw: its start (the Env, ARGV after OptionParser took
# --log out, the working directory, Bundler), the run events, and at_exit
# with the exiting status. Run 1 calls AppHandle#request_restart; run 2
# calls AppHandle#restart from a thread; run 3 calls it on the main thread
# inside the event loop; run 4 exits with 0. Each run tries to prevent the
# restart's exit request, which RESTART_EXIT_CODE ignores. Every process
# a restart starts is logged as a spawn.
#
# With --in-handler=restart, run 1 calls AppHandle#request_restart and
# then, in the exit request's handler, AppHandle#restart, which ends the
# process at once; run 2 exits. Only the restart that ended the process
# may start one. With --in-handler=exit, the handler calls exit(3)
# instead, and nothing restarts.
#
#   bundle exec ruby test/integration/fixtures/restart/app.rb --log=/tmp/restart.log

require_relative "../../support/fixture_app"

log = nil
in_handler = nil
OptionParser.new do |parser|
  parser.on("--log=PATH") { |path| log = path }
  parser.on("--in-handler=ACTION", %w[restart exit]) { |action| in_handler = action }
end.parse!(ARGV)
abort "usage: app.rb --log=PATH [--in-handler=restart|exit] [args...]" unless log

run = 1 + (File.exist?(log) ? File.readlines(log).count { |line| line.include?('"event":"started"') } : 0)
write = -> (entry) { File.open(log, "a") { |file| file.puts(JSON.generate({ run:, **entry })) } }
write.call(
  event: "started", pid: Process.pid, args_os: Tokra::Env.default.args_os, argv: ARGV, cwd: Dir.pwd,
  bundler: defined?(Bundler::Runtime) ? true : false, gemfile: ENV.fetch("BUNDLE_GEMFILE", nil)
)
at_exit { write.call(event: "at_exit", status: $!.is_a?(SystemExit) ? $!.status : nil) }

# Logs each process the restart starts, so the test can count them.
Process.singleton_class.prepend(Module.new do
  define_method(:spawn) { |*command, **options| super(*command, **options).tap { |pid| write.call(event: "spawn", pid:) } }
end)

app = Tokra::Builder.default.title("Tokra integration: restart").size(320, 240).build
FixtureApp.background(app)

app.run do |handle, event|
  case event
  when Tokra::RunEvent::Ready
    write.call(event: "ready")
    case [run, in_handler]
    in [1, _] then handle.request_restart
    in [2, nil] then Thread.new { handle.restart }
    in [3, nil] then Thread.new { handle.run_on_main_thread { handle.restart } }
    else handle.exit(0)
    end
  when Tokra::RunEvent::ExitRequested
    write.call(event: "exit-requested", code: event.code)
    event.api.prevent_exit if event.code == Tokra::RESTART_EXIT_CODE
    if run == 1
      case in_handler
      when "restart" then handle.restart
      when "exit" then exit(3)
      end
    end
  when Tokra::RunEvent::Exit then write.call(event: "exit")
  end
end
