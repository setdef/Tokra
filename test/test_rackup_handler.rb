# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "rackup"
require "open3"
require "rbconfig"

# The `rackup -s tokra` command finds its handler through
# Rackup::Handler.get (rackup 2.3.1 lib/rackup/handler.rb), so this test
# resolves it the way the command does, without opening a window.
class TestRackupHandler < Minitest::Test
  def test_get_resolves_the_lowercase_name_the_command_passes
    assert_same Rack::Handler::Tokra, Rackup::Handler.get("tokra")
  end

  def test_get_resolves_the_capitalized_name
    assert_same Rack::Handler::Tokra, Rackup::Handler.get("Tokra")
  end

  def test_a_server_built_with_the_server_option_uses_the_handler
    assert_same Rack::Handler::Tokra, Rackup::Server.new(server: "tokra").server
  end

  def test_the_default_handler_follows_rackup_handler_in_the_environment
    previous = ENV["RACKUP_HANDLER"]
    ENV["RACKUP_HANDLER"] = "tokra"
    assert_same Rack::Handler::Tokra, Rackup::Handler.default
  ensure
    ENV["RACKUP_HANDLER"] = previous
  end

  def test_requiring_the_handler_file_without_rackup_is_harmless
    lib = File.expand_path("../lib", __dir__)
    _out, err, status = Open3.capture3(RbConfig.ruby, "-I", lib, "-e", 'require "rackup/handler/tokra"')

    assert_predicate status, :success?, err
  end
end
