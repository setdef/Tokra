# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "bundler"

# Where each plugin's own bundle installs (Plan 069).
#
# plugins:test and the real-window tasks install each plugin's Gemfile
# apart from the root's, in an unbundled environment. A plugin has no
# bundle settings of its own, so its gems went to Ruby's gem folder,
# which on Windows lay so deep under mise's install of RubyInstaller's
# head build of Ruby 4.1 that ferro-rfd's Cargo files passed the 260
# characters Windows allows a path. So a plugin's bundle installs where the root
# bundle does, vendor/bundle on CI, and finds there the Ferro gems the
# root already compiled.
module PluginBundle
  # The environment for a plugin's bundle commands: BUNDLE_PATH at
  # +path+, the root bundle's install path, read against +root+, or
  # nothing when the root bundle installs where Ruby does.
  def self.env(path = Bundler.settings[:path], root: Bundler.root)
    path ? { "BUNDLE_PATH" => File.expand_path(path, root) } : {}
  end
end
