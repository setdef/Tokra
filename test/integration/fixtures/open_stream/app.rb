# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Fixture for real_app_test.rb: a child that opens no window, prints a
# line to each stream, and exits, while a grandchild it starts keeps its
# stdout open, as a process that inherited the pipes would after a hung
# fixture is killed (plan 051). It prints the grandchild's pid, so the
# test can end it.
#
#   bundle exec ruby test/integration/fixtures/open_stream/app.rb

$stdout.sync = true
$stderr.sync = true

puts "PROGRESS ready 0.000"
warn "stderr before the end"
grandchild = Process.spawn(RbConfig.ruby, "-e", "sleep 120", err: File::NULL)
Process.detach(grandchild)
puts "GRANDCHILD #{grandchild}"
