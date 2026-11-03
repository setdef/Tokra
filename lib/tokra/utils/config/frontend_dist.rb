# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: FrontendDist adapted from tauri-utils src/config.rs:2940-2962
#   at vendor/tauri 9f0306fbc
#++

module Tokra
  module Utils
    module Config
      # Where your app's built frontend lives.
      #
      # A packaged app shows pages from its built frontend: a directory of
      # files, a list of files, or a site on the web. The config names
      # which, and the app's URL follows from it.
      #
      # Tokra reads it now. A URL acts as the app's URL once the builder
      # takes a context (plan 054, decision 10); embedding a directory or
      # files waits for the assets plan, and until then your Rack app
      # serves <tt>tokra://</tt> (decision 13).
      #
      # Mirrors Tauri's untagged <tt>FrontendDist</tt> (config.rs:2940-2962).
      #
      # === Examples
      #
      #   # "frontendDist": "../dist"
      #   build.frontend_dist  #=> #<data Tokra::Utils::Config::FrontendDist::Directory path=#<Pathname:../dist>>
      #
      #   # "frontendDist": "https://example.com/app"
      #   build.frontend_dist.url.as_str  #=> "https://example.com/app"
      module FrontendDist
        # A site on the web, as a Ferro::Url::Url, url's own URL.
        class Url < Data.define(:url)
        end

        # A directory of files, as a Pathname.
        class Directory < Data.define(:path)
        end

        # A list of files, as Pathnames.
        class Files < Data.define(:paths)
        end

        # Reads +value+, a JSON value, as serde reads the untagged enum: a
        # URL, then a path, then a list of paths.
        def self.deserialize(value) # :nodoc:
          Ipc::Serde.untagged(value, "FrontendDist", [
            -> (raw) { Url.new(url: Utils::Config.url(raw)) },
            -> (raw) { Directory.new(path: Utils::Config.path(raw)) },
            -> (raw) { Files.new(paths: Utils::Config.sequence(raw) { |path| Utils::Config.path(path) }) },
          ])
        end
      end
    end
  end
end

#--
# SPDX-SnippetEnd
#++
