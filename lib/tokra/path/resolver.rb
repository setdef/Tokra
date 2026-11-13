# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "etc"
require_relative "std"
require_relative "error"
require_relative "base_directory"
require_relative "safe_path_buf"

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: PathResolver adapted from tauri/crates/tauri/src/path/desktop.rs and path/mod.rs;
#                      the platform notes are Tauri's rustdoc

module Tokra
  # Where an app keeps its files, and the path rules it joins them by.
  #
  # Mirrors Tauri's <tt>tauri::path</tt> module: PathResolver, which
  # every handle answers as +path+, BaseDirectory, SafePathBuf, and the
  # +path+ core plugin that answers <tt>@tauri-apps/api/path</tt>.
  module Path
    # Answers where the user's and the app's directories are.
    #
    # Every platform keeps settings, caches, logs, and the user's
    # documents in different places, and each has rules for an app's own
    # folder inside them. A path you build by hand, such as
    # <tt>~/.myapp</tt>, ignores those rules: macOS users look in
    # Application Support, Linux users set <tt>XDG_CONFIG_HOME</tt>, and
    # Windows users roam their AppData.
    #
    # PathResolver answers each directory the way Tauri's does on each
    # platform, as a Pathname. The app directories add the config's
    # +identifier+, so <tt>app_data_dir</tt> is
    # <tt>~/Library/Application Support/com.example.app</tt> on macOS. Each
    # method raises Error::UnknownPath when the platform has no such
    # directory.
    #
    # Use it through +path+ on any handle: the App, an AppHandle, a
    # Window, or a Webview. #resolve joins a relative path to a
    # BaseDirectory, and #parse reads a path that starts with one's
    # variable.
    #
    # Mirrors Tauri's <tt>tauri::path::PathResolver</tt>
    # (path/desktop.rs, path/mod.rs:249-363). Tauri reads the directories
    # from the dirs crate. Tokra's native extension binds only its
    # +home_dir+ and +data_local_dir+ so far, so #home_dir,
    # #local_data_dir, #app_local_data_dir, #app_log_dir, and #temp_dir
    # answer today, and the others raise NotImplementedError naming the
    # dirs function they wait on (plan 063).
    #
    # === Examples
    #
    #   app.path.app_log_dir      #=> #<Pathname:/Users/me/Library/Logs/com.example.app>
    #   app.path.resolve("db.sqlite", Tokra::Path::BaseDirectory::AppLocalData)
    #   app.path.parse("$HOME/.bashrc")  #=> #<Pathname:/Users/me/.bashrc>
    class PathResolver
      # Creates the resolver for +app+, any handle with a +config+, whose
      # +identifier+ names the app directories. The path plugin makes one
      # for each app; reach it with +path+.
      #
      # [dirs] the dirs crate's functions, each answering a String or
      #        +nil+; Tokra::Native by default.
      # [target] the Utils::Platform::Target whose rules apply; the
      #          host's by default.
      # [env] the environment #temp_dir reads; ENV by default.
      def initialize(app, dirs: Native, target: Utils::Platform::Target.current, env: ENV)
        @app = app
        @dirs = dirs
        @target = target
        @env = env
      end

      # The Utils::Platform::Target whose rules this resolver follows.
      attr_reader :target

      # The final component of +path+, if it is a name. For a file this
      # is its name, and for a directory its name. Returns +nil+ when the
      # path ends in <tt>..</tt>, a root, or nothing.
      #
      # Prefer File.basename when you know the path is a plain one; this
      # follows Rust's rules, as the page's +basename+ and +extname+ do.
      #
      # === Example
      #
      #   app.path.file_name("/a/b.json")  #=> "b.json"
      def file_name(path)
        std.file_name(::File.path(path))
      end

      # The user's audio directory.
      #
      # - Linux: <tt>XDG_MUSIC_DIR</tt>, from xdg-user-dirs.
      # - macOS: <tt>$HOME/Music</tt>.
      # - Windows: <tt>{FOLDERID_Music}</tt>.
      #
      # === Example
      #
      #   app.path.audio_dir
      def audio_dir
        dir(:audio_dir)
      end

      # The user's cache directory.
      #
      # - Linux: <tt>$XDG_CACHE_HOME</tt> or <tt>$HOME/.cache</tt>.
      # - macOS: <tt>$HOME/Library/Caches</tt>.
      # - Windows: <tt>{FOLDERID_LocalAppData}</tt>.
      #
      # === Example
      #
      #   app.path.cache_dir
      def cache_dir
        dir(:cache_dir)
      end

      # The user's config directory.
      #
      # - Linux: <tt>$XDG_CONFIG_HOME</tt> or <tt>$HOME/.config</tt>.
      # - macOS: <tt>$HOME/Library/Application Support</tt>.
      # - Windows: <tt>{FOLDERID_RoamingAppData}</tt>.
      #
      # === Example
      #
      #   app.path.config_dir
      def config_dir
        dir(:config_dir)
      end

      # The user's data directory.
      #
      # - Linux: <tt>$XDG_DATA_HOME</tt> or <tt>$HOME/.local/share</tt>.
      # - macOS: <tt>$HOME/Library/Application Support</tt>.
      # - Windows: <tt>{FOLDERID_RoamingAppData}</tt>.
      #
      # === Example
      #
      #   app.path.data_dir
      def data_dir
        dir(:data_dir)
      end

      # The user's local data directory.
      #
      # - Linux: <tt>$XDG_DATA_HOME</tt> or <tt>$HOME/.local/share</tt>.
      # - macOS: <tt>$HOME/Library/Application Support</tt>.
      # - Windows: <tt>{FOLDERID_LocalAppData}</tt>.
      #
      # === Example
      #
      #   app.path.local_data_dir
      def local_data_dir
        dir(:data_local_dir)
      end

      # The user's desktop directory.
      #
      # - Linux: <tt>XDG_DESKTOP_DIR</tt>, from xdg-user-dirs.
      # - macOS: <tt>$HOME/Desktop</tt>.
      # - Windows: <tt>{FOLDERID_Desktop}</tt>.
      #
      # === Example
      #
      #   app.path.desktop_dir
      def desktop_dir
        dir(:desktop_dir)
      end

      # The user's document directory.
      #
      # - Linux: <tt>XDG_DOCUMENTS_DIR</tt>, from xdg-user-dirs.
      # - macOS: <tt>$HOME/Documents</tt>.
      # - Windows: <tt>{FOLDERID_Documents}</tt>.
      #
      # === Example
      #
      #   app.path.document_dir
      def document_dir
        dir(:document_dir)
      end

      # The user's download directory.
      #
      # - Linux: <tt>XDG_DOWNLOAD_DIR</tt>, from xdg-user-dirs.
      # - macOS: <tt>$HOME/Downloads</tt>.
      # - Windows: <tt>{FOLDERID_Downloads}</tt>.
      #
      # === Example
      #
      #   app.path.download_dir
      def download_dir
        dir(:download_dir)
      end

      # The user's executable directory.
      #
      # - Linux: <tt>$XDG_BIN_HOME</tt> or <tt>$HOME/.local/bin</tt>, as
      #   dirs 6.0.0 answers. (Tauri's rustdoc still describes an older
      #   rule, <tt>$XDG_BIN_HOME/../bin</tt>.)
      # - macOS: none; raises Error::UnknownPath.
      # - Windows: none; raises Error::UnknownPath.
      #
      # === Example
      #
      #   app.path.executable_dir
      def executable_dir
        dir(:executable_dir)
      end

      # The user's font directory.
      #
      # - Linux: <tt>$XDG_DATA_HOME/fonts</tt> or
      #   <tt>$HOME/.local/share/fonts</tt>.
      # - macOS: <tt>$HOME/Library/Fonts</tt>.
      # - Windows: none; raises Error::UnknownPath.
      #
      # === Example
      #
      #   app.path.font_dir
      def font_dir
        dir(:font_dir)
      end

      # The user's home directory.
      #
      # - Linux: <tt>$HOME</tt>.
      # - macOS: <tt>$HOME</tt>.
      # - Windows: <tt>{FOLDERID_Profile}</tt>.
      #
      # === Example
      #
      #   app.path.home_dir  #=> #<Pathname:/Users/me>
      def home_dir
        dir(:home_dir)
      end

      # The user's picture directory.
      #
      # - Linux: <tt>XDG_PICTURES_DIR</tt>, from xdg-user-dirs.
      # - macOS: <tt>$HOME/Pictures</tt>.
      # - Windows: <tt>{FOLDERID_Pictures}</tt>.
      #
      # === Example
      #
      #   app.path.picture_dir
      def picture_dir
        dir(:picture_dir)
      end

      # The user's public directory.
      #
      # - Linux: <tt>XDG_PUBLICSHARE_DIR</tt>, from xdg-user-dirs.
      # - macOS: <tt>$HOME/Public</tt>.
      # - Windows: <tt>{FOLDERID_Public}</tt>.
      #
      # === Example
      #
      #   app.path.public_dir
      def public_dir
        dir(:public_dir)
      end

      # The user's runtime directory.
      #
      # - Linux: <tt>$XDG_RUNTIME_DIR</tt>.
      # - macOS: none; raises Error::UnknownPath.
      # - Windows: none; raises Error::UnknownPath.
      #
      # === Example
      #
      #   app.path.runtime_dir
      def runtime_dir
        dir(:runtime_dir)
      end

      # The user's template directory.
      #
      # - Linux: <tt>XDG_TEMPLATES_DIR</tt>, from xdg-user-dirs.
      # - macOS: none; raises Error::UnknownPath.
      # - Windows: <tt>{FOLDERID_Templates}</tt>.
      #
      # === Example
      #
      #   app.path.template_dir
      def template_dir
        dir(:template_dir)
      end

      # The user's video directory.
      #
      # - Linux: <tt>XDG_VIDEOS_DIR</tt>, from xdg-user-dirs.
      # - macOS: <tt>$HOME/Movies</tt>.
      # - Windows: <tt>{FOLDERID_Videos}</tt>.
      #
      # === Example
      #
      #   app.path.video_dir
      def video_dir
        dir(:video_dir)
      end

      # The directory of the app's bundled resources.
      #
      # Raises NotImplementedError. Tauri finds it beside the app's
      # executable (tauri-utils platform.rs:264-336), which for a Tokra
      # app is the Ruby interpreter. A packaged Tokra app will keep its
      # resources in <tt>tokra-packaged/resources/</tt> (ADR 015), and
      # this answers once that packaging exists (plan 063, decision 7).
      # Until then, find a resource from your script's directory, with
      # <tt>__dir__</tt>.
      #
      # === Example
      #
      #   app.path.resource_dir  # raises NotImplementedError
      def resource_dir
        raise NotImplementedError,
          "resource_dir is not available yet: Tokra does not yet package an app's resources (see plan 063)"
      end

      # The suggested directory for your app's config files:
      # #config_dir, then the config's +identifier+.
      #
      # === Example
      #
      #   app.path.app_config_dir.join("settings.json")
      def app_config_dir
        dir(:config_dir).then { |base| join(base, identifier) }
      end

      # The suggested directory for your app's data files: #data_dir,
      # then the config's +identifier+.
      #
      # === Example
      #
      #   app.path.app_data_dir.join("app.db")
      def app_data_dir
        dir(:data_dir).then { |base| join(base, identifier) }
      end

      # The suggested directory for your app's local data files:
      # #local_data_dir, then the config's +identifier+.
      #
      # === Example
      #
      #   app.path.app_local_data_dir
      def app_local_data_dir
        dir(:data_local_dir).then { |base| join(base, identifier) }
      end

      # The suggested directory for your app's cache files: #cache_dir,
      # then the config's +identifier+.
      #
      # === Example
      #
      #   app.path.app_cache_dir
      def app_cache_dir
        dir(:cache_dir).then { |base| join(base, identifier) }
      end

      # The suggested directory for your app's log files.
      #
      # - Linux: #local_data_dir, then the +identifier+, then
      #   <tt>logs</tt>.
      # - macOS: #home_dir, then <tt>Library/Logs</tt>, then the
      #   +identifier+.
      # - Windows: #local_data_dir, then the +identifier+, then
      #   <tt>logs</tt>.
      #
      # === Example
      #
      #   app.path.app_log_dir  #=> #<Pathname:/Users/me/Library/Logs/com.example.app>
      def app_log_dir
        if @target == Utils::Platform::Target::MacOS
          join(join(dir(:home_dir), "Library/Logs"), identifier)
        else
          join(join(dir(:data_local_dir), identifier), "logs")
        end
      end

      # A temporary directory, as Rust's <tt>std::env::temp_dir</tt>
      # answers it.
      #
      # - Linux: <tt>$TMPDIR</tt> when set, else <tt>/tmp</tt>.
      # - macOS: <tt>$TMPDIR</tt> when set, else the user's own
      #   temporary directory, which Ruby's Etc.systmpdir asks macOS for
      #   as Rust does, else <tt>/tmp</tt>.
      # - Windows: <tt>%TMP%</tt>, <tt>%TEMP%</tt>, <tt>%USERPROFILE%</tt>,
      #   or the Windows directory, the first that is set, ending in a
      #   backslash, as GetTempPath2W answers a process that is not
      #   SYSTEM.
      #
      # === Example
      #
      #   app.path.temp_dir
      def temp_dir
        Pathname.new((@target == Utils::Platform::Target::Windows) ? windows_temp_dir : unix_temp_dir)
      end

      # +path+ joined to the directory +base_directory+ names, as
      # PathBuf::push joins them: an absolute +path+ stands alone. Raises
      # what the directory's own method raises.
      #
      # A path under BaseDirectory::Resource follows the bundler's rule
      # for resources: its root becomes <tt>_root_</tt> and each
      # <tt>..</tt> becomes <tt>_up_</tt>.
      #
      # === Example
      #
      #   app.path.resolve("path/to/something", Tokra::Path::BaseDirectory::Config)
      #   #=> #<Pathname:/home/me/.config/path/to/something>   (on Linux)
      def resolve(path, base_directory)
        resolve_path(base_directory, ::File.path(path))
      end

      # +path+, with a leading BaseDirectory variable resolved, and every
      # later <tt>..</tt> dropped.
      #
      # === Example
      #
      #   app.path.parse("$HOME/.bashrc")  #=> #<Pathname:/home/me/.bashrc>   (on Linux)
      def parse(path)
        first, *rest = std.components(::File.path(path))
        parsed = ""
        if first
          directory = BaseDirectory.from_variable(first.as_os_str) if first.kind == :normal
          parsed = std.push(parsed, directory ? resolve_path(directory).to_s : first.as_os_str)
        end
        rest.each do |component|
          parsed = std.push(parsed, component.as_os_str) unless component.kind == :parent_dir
        end
        Pathname.new(parsed)
      end

      # The directory +directory+ names, with +path+ joined to it when
      # given, as Tauri's resolve_path (mod.rs:306-363), which the page's
      # <tt>resolve_directory</tt> calls.
      def resolve_path(directory, path = nil) # :nodoc:
        base = directory_for(directory).to_s
        return Pathname.new(base) if path.nil?

        Pathname.new(std.push(base, (directory == BaseDirectory::Resource) ? resource_path(path) : path))
      end

      private def directory_for(directory)
        case directory
        when BaseDirectory::Audio then audio_dir
        when BaseDirectory::Cache then cache_dir
        when BaseDirectory::Config then config_dir
        when BaseDirectory::Data then data_dir
        when BaseDirectory::LocalData then local_data_dir
        when BaseDirectory::Document then document_dir
        when BaseDirectory::Download then download_dir
        when BaseDirectory::Picture then picture_dir
        when BaseDirectory::Public then public_dir
        when BaseDirectory::Video then video_dir
        when BaseDirectory::Resource then resource_dir
        when BaseDirectory::Temp then temp_dir
        when BaseDirectory::AppConfig then app_config_dir
        when BaseDirectory::AppData then app_data_dir
        when BaseDirectory::AppLocalData then app_local_data_dir
        when BaseDirectory::AppCache then app_cache_dir
        when BaseDirectory::AppLog then app_log_dir
        when BaseDirectory::Desktop then desktop_dir
        when BaseDirectory::Executable then executable_dir
        when BaseDirectory::Font then font_dir
        when BaseDirectory::Home then home_dir
        when BaseDirectory::Runtime then runtime_dir
        else template_dir
        end
      end

      # The bundler's path for a resource: a prefix and <tt>.</tt> drop,
      # a root is <tt>_root_</tt>, and a parent <tt>_up_</tt>.
      private def resource_path(path)
        std.components(path).reduce("") do |mapped, component|
          case component.kind
          when :root_dir then std.push(mapped, "_root_")
          when :parent_dir then std.push(mapped, "_up_")
          when :normal then std.push(mapped, component.as_os_str)
          else mapped
          end
        end
      end

      # The dirs crate's answer for +function+, as a Pathname. Raises
      # Error::UnknownPath for +nil+, and NotImplementedError when the
      # collaborator does not bind +function+.
      private def dir(function)
        unless @dirs.respond_to?(function)
          raise NotImplementedError,
            "#{function} is not available yet: Tokra does not bind the dirs crate's #{function} (see plan 063)"
        end

        answer = @dirs.public_send(function) #: String?
        raise Error::UnknownPath unless answer

        Pathname.new(answer)
      end

      private def join(base, name)
        Pathname.new(std.push(base.to_s, name))
      end

      private def identifier
        @app.config.identifier
      end

      private def std
        Std.for(@target)
      end

      private def unix_temp_dir
        return @env["TMPDIR"].to_s if @env.key?("TMPDIR")
        # Steep's library set has no etc signatures.
        return Etc.systmpdir.to_s if @target == Utils::Platform::Target::MacOS # steep:ignore UnknownConstant

        "/tmp"
      end

      private def windows_temp_dir
        found = %w[TMP TEMP USERPROFILE].map { |name| @env[name] }.find { |value| value && !value.empty? }
        found ||= @env["SystemRoot"] || @env["windir"] || "C:\\Windows"
        found.end_with?("\\") ? found : "#{found}\\"
      end
    end

    # The resolver's name before Tokra took Tauri's, PathResolver. The log
    # plugin names it.
    Resolver = PathResolver
  end
end

# SPDX-SnippetEnd

require_relative "plugin"
