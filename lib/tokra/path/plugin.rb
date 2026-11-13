# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetCopyrightText: The Cargo Project Developers (normalize_path)
# SPDX-SnippetCopyrightText: Erick Tryzelaar and David Tolnay (serde, serde_json)
# SPDX-SnippetComment: the path plugin and its init script adapted from tauri/crates/tauri/src/path/plugin.rs
#                      and path/init.js; normalize_path is cargo's, as Tauri took it; the argument messages
#                      are serde's as serde_json produces them

module Tokra
  module Path
    # Core plugin answering <tt>@tauri-apps/api/path</tt>.
    #
    # A page that saves a file asks where: <tt>appDataDir()</tt>,
    # <tt>join(dir, 'notes.md')</tt>. Each of those functions invokes a
    # <tt>plugin:path|*</tt> command, and reads the platform's separator
    # and delimiter from what this plugin's init script defines.
    #
    # This plugin answers those commands with Tauri's answers and
    # rejections, and manages the app's PathResolver, which every handle
    # returns as +path+. Tokra registers it first of its core plugins, as
    # Tauri does, so you never register it yourself.
    #
    # Each command's work is a class method here, taking the Std rules of
    # a platform, so you can call it from Ruby too.
    #
    # Mirrors Tauri's <tt>path/plugin.rs</tt>.
    #
    # === Examples
    #
    #   app.path  #=> the Tokra::Path::PathResolver this plugin manages
    #   Tokra::Path::Plugin.join(Tokra::Path::Std::UNIX, ["a", "b/../c"])  #=> "a/c"
    class Plugin < Tokra::Plugin
      # Registers the plugin with +app+, an AppHandle, and manages a
      # PathResolver for it, as Tauri's setup does (plugin.rs:236-249).
      # +target+, a Utils::Platform::Target, picks the platform whose
      # rules and separators apply; the host's by default.
      def initialize(app, config = {}, target: Utils::Platform::Target.current)
        super(app, config)
        @target = target
        app.manage(PathResolver.new(app, target:))
      end

      # Returns the plugin identifier.
      def name
        "path"
      end

      # Defines <tt>window.__TAURI_INTERNALS__.plugins.path</tt> with the
      # platform's +sep+ and +delimiter+: <tt>\\</tt> and <tt>;</tt> on
      # Windows, <tt>/</tt> and <tt>:</tt> elsewhere (plugin.rs:204-221,
      # init.js).
      def initialization_script
        windows = @target == Utils::Platform::Target::Windows
        INIT_SCRIPT
          .sub("__TEMPLATE_sep__", Plugin.javascript_string(windows ? "\\" : "/"))
          .sub("__TEMPLATE_delimiter__", Plugin.javascript_string(windows ? ";" : ":"))
      end

      # Answers +resolve_directory+, +resolve+, +normalize+, +join+,
      # +dirname+, +extname+, +basename+, and +is_absolute+
      # (plugin.rs:223-234). Returns +false+ for any other command.
      #
      # An argument that does not read rejects with Tauri's
      # <tt>invalid args</tt> message, and a command that fails with the
      # error's message, as Tauri's command layer does. A directory Tokra
      # cannot resolve yet rejects with NotImplementedError's message.
      def extend_api(invoke)
        case invoke.command
        when "resolve_directory" then resolve_directory(invoke)
        when "resolve" then invoke.resolve(Plugin.resolve(std, item(invoke, "paths").strings, current_dir))
        when "normalize" then invoke.resolve(Plugin.normalize(std, item(invoke, "path").string))
        when "join" then invoke.resolve(Plugin.join(std, item(invoke, "paths").strings))
        when "dirname" then invoke.resolve(Plugin.dirname(std, item(invoke, "path").string))
        when "extname" then invoke.resolve(Plugin.extname(std, item(invoke, "path").string))
        when "basename" then basename(invoke)
        when "is_absolute" then invoke.resolve(Plugin.is_absolute(std, item(invoke, "path").string))
        else return false
        end
        true
      rescue Error::InvalidArgs,
        Error::UnknownPath,
        Error::NoParent,
        Error::NoExtension,
        Error::NoBasename,
        Error::CurrentDir,
        NotImplementedError => e

        invoke.reject(e.message)
        true
      end

      # +paths+ pushed one by one onto +current_dir+, so an absolute one
      # starts over, then normalized (plugin.rs:98-111).
      #
      # === Example
      #
      #   Tokra::Path::Plugin.resolve(Tokra::Path::Std::UNIX, ["/foo/bar", "/tmp/file", "baz"], "/home/me")
      #   #=> "/tmp/file/baz"
      def self.resolve(std, paths, current_dir)
        path = paths.reduce(current_dir) { |joined, next_path| std.push(joined, next_path) }
        std.simplified(normalize_path(std, path))
      end

      # +path+ with <tt>.</tt> and <tt>..</tt> taken out, as Node's
      # +normalize+ answers <tt>..</tt>, <tt>.</tt>, and a trailing
      # separator (plugin.rs:113-132). An empty path stays empty.
      #
      # === Example
      #
      #   Tokra::Path::Plugin.normalize(Tokra::Path::Std::UNIX, "/a/b/../c/")  #=> "/a/c/"
      def self.normalize(std, path)
        normalized = std.simplified(normalize_path_no_absolute(std, path))
        return ".." if normalized.empty? && path == ".."
        return "." if normalized.empty? && path == "."

        # Tauri's check, (!p.ends_with('/') || !p.ends_with('\\')), is
        # always true, so a separator follows even one already there.
        normalized += std.separator if path.end_with?("/", "\\")
        normalized
      end

      # +paths+ joined with the platform's separator and normalized, an
      # absolute path among them joining like any other
      # (plugin.rs:134-161).
      #
      # === Example
      #
      #   Tokra::Path::Plugin.join(Tokra::Path::Std::WINDOWS, ["a", "/b", "c"])  #=> "a\\b\\c"
      def self.join(std, paths)
        joined = paths.map { |path| (path.empty? || path.end_with?("/", "\\")) ? path : "#{path}#{std.separator}" }.join
        normalized = std.simplified(normalize_path_no_absolute(std, joined))
        normalized.empty? ? "." : normalized
      end

      # The directory of +path+. Raises Error::NoParent when +path+ ends
      # in a root or a prefix, or is empty (plugin.rs:163-169).
      #
      # === Example
      #
      #   Tokra::Path::Plugin.dirname(Tokra::Path::Std::UNIX, "/a/b")  #=> "/a"
      def self.dirname(std, path)
        parent = std.parent(path)
        raise Error::NoParent unless parent

        std.simplified(parent)
      end

      # The extension of +path+'s file name, without the dot. Raises
      # Error::NoExtension when there is none (plugin.rs:171-181).
      #
      # === Example
      #
      #   Tokra::Path::Plugin.extname(Tokra::Path::Std::UNIX, "a/b.json")  #=> "json"
      def self.extname(std, path)
        file_name = std.file_name(path)
        raise Error::NoExtension unless file_name

        std.extension(file_name) || raise(Error::NoExtension)
      end

      # The file name of +path+, with +ext+ cut off its end when given and
      # there. Raises Error::NoBasename when the path ends in no name
      # (plugin.rs:183-197).
      #
      # === Example
      #
      #   Tokra::Path::Plugin.basename(Tokra::Path::Std::UNIX, "/a/b.json", ".json")  #=> "b"
      def self.basename(std, path, ext)
        file_name = std.file_name(path)
        raise Error::NoBasename unless file_name

        (ext && file_name.end_with?(ext)) ? file_name.delete_suffix(ext) : file_name
      end

      # Whether +path+ is absolute: on Windows, with a prefix and a root
      # (plugin.rs:199-202).
      #
      # === Example
      #
      #   Tokra::Path::Plugin.is_absolute(Tokra::Path::Std::WINDOWS, "C:\\a")  #=> true
      def self.is_absolute(std, path)
        std.absolute?(path)
      end

      # +path+ with <tt>.</tt> and <tt>..</tt> taken out, each component
      # pushed as PathBuf::push pushes it, cargo's normalize_path
      # (plugin.rs:16-43).
      def self.normalize_path(std, path) # :nodoc:
        components = std.components(path)
        normalized = (components.first&.kind == :prefix) ? components.shift&.as_os_str.to_s : ""
        components.each do |component|
          case component.kind
          when :root_dir, :normal then normalized = std.push(normalized, component.as_os_str)
          when :parent_dir then normalized = std.parent(normalized) || normalized
          end
        end
        normalized
      end

      # normalize_path, but a component joins as text, so an absolute
      # piece after the first does not replace what came before
      # (plugin.rs:45-86).
      def self.normalize_path_no_absolute(std, path) # :nodoc:
        components = std.components(path)
        normalized = (components.first&.kind == :prefix) ? components.shift&.as_os_str.to_s : ""
        components.each do |component|
          case component.kind
          when :root_dir then normalized = std.push(normalized, component.as_os_str)
          when :parent_dir then normalized = std.parent(normalized) || normalized
          when :normal
            normalized += std.separator unless normalized.empty? || normalized.end_with?("/", "\\")
            normalized += component.as_os_str
          end
        end
        normalized
      end

      # +text+ as serialize_to_javascript writes a template value: its
      # JSON inside <tt>JSON.parse('...')</tt>, with each backslash and
      # single quote escaped (serialize-to-javascript 0.1.2
      # lib.rs:188-238).
      def self.javascript_string(text) # :nodoc:
        "JSON.parse('#{JSON.generate(text).gsub(/[\\']/) { |char| "\\#{char}" }}')"
      end

      # path/init.js, whose two template values #initialization_script
      # fills in.
      INIT_SCRIPT = <<~JS # :nodoc:
        // Copyright 2019-2024 Tauri Programme within The Commons Conservancy
        // SPDX-License-Identifier: Apache-2.0
        // SPDX-License-Identifier: MIT

        Object.defineProperty(window.__TAURI_INTERNALS__.plugins, 'path', {
          value: {
            sep: __TEMPLATE_sep__,
            delimiter: __TEMPLATE_delimiter__
          }
        })
      JS

      private def resolve_directory(invoke)
        directory = item(invoke, "directory").deserialize { |value| BaseDirectory.deserialize(value) }
        path = item(invoke, "path").deserialize_option { |value| path_string(value) }
        resolved = app.path.resolve_path(directory, path)
        invoke.resolve(std.simplified(resolved.to_s))
      end

      private def basename(invoke)
        path = item(invoke, "path").deserialize { |value| borrowed_string(value) }
        ext = item(invoke, "ext").deserialize_option { |value| borrowed_string(value) }
        invoke.resolve(Plugin.basename(std, path, ext))
      end

      # The process's current directory as Rust's current_dir answers it:
      # Windows' with backslashes, which Ruby's Dir.pwd writes as slashes.
      private def current_dir
        pwd = Dir.pwd
        (@target == Utils::Platform::Target::Windows) ? pwd.tr("/", "\\") : pwd
      rescue SystemCallError => e
        # A nil message leaves the description alone, which Ruby allows
        # and core's RBS does not say.
        description = SystemCallError.new(nil, e.errno).message # steep:ignore ArgumentTypeMismatch
        raise Error::CurrentDir, "#{description} (os error #{e.errno})"
      end

      private def path_string(value)
        value.is_a?(String) ? value : raise(Ipc::CommandItem::Mismatch.invalid_type(value, "path string"))
      end

      private def borrowed_string(value)
        value.is_a?(String) ? value : raise(Ipc::CommandItem::Mismatch.invalid_type(value, "a borrowed string"))
      end

      private def item(invoke, key)
        Ipc::CommandItem.new(name: invoke.command, key:, payload: invoke.body)
      end

      private def std
        Std.for(@target)
      end
    end
  end
end

# SPDX-SnippetEnd
