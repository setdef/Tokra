# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../../tasks/plugin_bundle"

# Tests where a plugin's own bundle installs (Plan 069): where the root
# bundle does. A plugin's Gemfile has no bundle settings of its own, so
# its gems went to Ruby's gem folder, which on Windows lies so deep under
# mise's install of RubyInstaller's head build that ferro-rfd's Cargo
# files passed the 260 characters Windows allows a path, and dlltool and
# gcc found no file there.
class TestPluginBundle < Minitest::Test
  def test_a_plugin_bundle_installs_where_the_root_bundle_does
    assert_equal({ "BUNDLE_PATH" => "/work/tokra/vendor/bundle" }, PluginBundle.env("vendor/bundle", root: "/work/tokra"))
    assert_equal({ "BUNDLE_PATH" => "/elsewhere/gems" }, PluginBundle.env("/elsewhere/gems", root: "/work/tokra"))
  end

  def test_with_no_root_path_a_plugin_bundle_installs_where_ruby_installs_gems
    assert_empty PluginBundle.env(nil, root: "/work/tokra")
  end

  def test_by_default_it_reads_the_root_bundle_s_settings
    expected = Bundler.settings[:path] ? { "BUNDLE_PATH" => File.expand_path(Bundler.settings[:path], Bundler.root) } : {}

    assert_equal expected, PluginBundle.env
  end
end
