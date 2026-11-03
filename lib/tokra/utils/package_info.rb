# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: PackageInfo adapted from tauri-utils src/lib.rs:43-58
#   at vendor/tauri 9f0306fbc
#++

module Tokra
  module Utils
    # Your app's name, version, and authorship.
    #
    # An about box shows your app's name and version, a desktop file names
    # your app, and a plugin may print its version in a log. Each reads
    # them from the same place, so they agree.
    #
    # Tokra.generate_context builds one from your config: +name+ is
    # <tt>productName</tt>, and +version+ is <tt>version</tt>. Tauri takes
    # what the config leaves out from the app's <tt>Cargo.toml</tt>, which
    # a Ruby app does not have, so Tokra takes it from what plays that
    # part: +name+ falls back to the entry script's name without its
    # extension, +version+ to <tt>"0.0.0"</tt> (Cargo's version for a
    # package that names none), +authors+ and +description+ are empty, as
    # Cargo leaves them for a manifest without them, and +crate_name+ is
    # the entry script's name.
    #
    # +version+ is a String, not a parsed version: Tauri's callers only
    # print it, and Ruby's Gem::Version orders prereleases differently
    # from semver.
    #
    # Mirrors Tauri's <tt>PackageInfo</tt> (tauri-utils src/lib.rs:43-58).
    #
    # === Examples
    #
    #   context = Tokra.generate_context
    #   context.package_info.name     #=> "My App"
    #   context.package_info.version  #=> "1.2.0"
    #
    #   context.package_info = context.package_info.with(version: "1.2.1")
    class PackageInfo < Data.define(:name, :version, :authors, :description, :crate_name)
    end
  end
end

#--
# SPDX-SnippetEnd
#++
