# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: The Rust Project Developers
# SPDX-SnippetCopyrightText: Kornel Lesiński (dunce)
# SPDX-SnippetComment: std::path from Rust 1.99.0's library/std/src/path.rs, sys/path/unix.rs,
#                      sys/path/windows.rs, and sys/path/windows_prefix.rs; simplified from dunce 1.0.5

module Tokra
  module Path
    # Rust's std::path, as each desktop platform parses a path.
    #
    # Tauri builds every directory and answers every path command with
    # std::path: PathBuf::push, Path::parent, Path::file_name, and the
    # Components iterator underneath them. Ruby's File and Pathname split
    # paths by other rules: they keep a <tt>.</tt> component and a
    # trailing separator, and on Windows they write <tt>/</tt> and know no
    # verbatim prefix. So the path API asks this class instead.
    #
    # UNIX and WINDOWS are its two values, one for each family, and
    # Std.for picks the one for an app's target, so a test checks both on
    # any host. Paths are Strings; the separators and dots it looks at
    # are ASCII, so it splits by character as Rust splits by byte.
    #
    # Ports Rust 1.99.0's std::path (<tt>path.rs</tt>: Components,
    # PathBuf::_push, parent, file_name, extension, file_stem;
    # <tt>sys/path/windows_prefix.rs</tt>: parse_prefix) and dunce 1.0.5's
    # simplified, which Tauri calls on every path it returns.
    class Std # :nodoc: all
      # A component of a path, as Rust's Component names it: +kind+ is
      # one of <tt>:prefix</tt>, <tt>:root_dir</tt>, <tt>:cur_dir</tt>,
      # <tt>:parent_dir</tt>, and <tt>:normal</tt>; +as_os_str+ is its
      # text (a root is the platform's separator); and +prefix+ is the
      # parsed Prefix of a <tt>:prefix</tt>.
      class Component < Data.define(:kind, :as_os_str, :prefix)
      end

      # A Windows path prefix, as Rust's Prefix enum names it: +kind+ is
      # one of <tt>:verbatim</tt>, <tt>:verbatim_unc</tt>,
      # <tt>:verbatim_disk</tt>, <tt>:device_ns</tt>, <tt>:unc</tt>, and
      # <tt>:disk</tt>, and +parts+ are its fields (a drive letter, or a
      # server and share).
      class Prefix < Data.define(:kind, :parts)
        # The prefix's length in the path, as Prefix::len counts it.
        def len
          first = parts.first.to_s
          second = parts[1]
          case kind
          when :verbatim then 4 + first.length
          when :verbatim_unc then 8 + first.length + share_length(second)
          when :verbatim_disk then 6
          when :unc then 2 + first.length + share_length(second)
          when :device_ns then 4 + first.length
          else 2
          end
        end

        # Whether the prefix begins with <tt>\\?\</tt>.
        def verbatim?
          %i[verbatim verbatim_unc verbatim_disk].include?(kind)
        end

        # Whether the prefix is a drive, such as <tt>C:</tt>.
        def drive?
          kind == :disk
        end

        # Whether a path with this prefix has a root without a separator:
        # every prefix but a drive's.
        def implicit_root?
          !drive?
        end

        private def share_length(share)
          share.to_s.empty? ? 0 : 1 + share.to_s.length
        end
      end

      # The parsing states of Rust's Components, in order.
      STATES = { prefix: 0, start_dir: 1, body: 2, done: 3 }.freeze

      # Rust's Components: a path being taken apart from both ends.
      class Components
        # The part of the path not yet taken.
        attr_reader :path

        # The path's Prefix, or +nil+.
        attr_reader :prefix

        # Starts taking +path+ apart by +std+'s rules.
        def initialize(std, path)
          @std = std
          @path = path
          @prefix = std.parse_prefix(path)
          @has_physical_root = std.physical_root?(path, @prefix)
          @front = std.windows? ? STATES[:prefix] : STATES[:start_dir]
          @back = STATES[:body]
        end

        # The length of the prefix, if any.
        def prefix_len
          @prefix&.len || 0
        end

        # Whether the prefix is verbatim.
        def prefix_verbatim?
          @prefix&.verbatim? || false
        end

        # How much of the prefix is left to take.
        def prefix_remaining
          (@front == STATES[:prefix]) ? prefix_len : 0
        end

        # Whether the path has a root, physical or implied by its prefix.
        def has_root?
          @has_physical_root || (@prefix&.implicit_root? || false)
        end

        # Every component left, from the front.
        def to_a
          components = [] #: Array[Component]
          while (component = self.next)
            components << component
          end
          components
        end

        # The next component from the front, or +nil+.
        def next
          until finished?
            case @front
            when STATES[:body]
              if @path.empty?
                @front = STATES[:done]
              else
                size, component = parse_next_component
                @path = @path[size..].to_s
                return component if component
              end
            when STATES[:start_dir]
              @front = STATES[:body]
              if @has_physical_root
                @path = @path[1..].to_s
                return component(:root_dir, @std.separator)
              elsif (prefix = @prefix)
                return component(:root_dir, @std.separator) if prefix.implicit_root? && !prefix.verbatim?
              elsif include_cur_dir?
                @path = @path[1..].to_s
                return component(:cur_dir, ".")
              end
            else
              @front = STATES[:start_dir]
              if prefix_len.positive?
                raw = @path[0, prefix_len].to_s
                @path = @path[prefix_len..].to_s
                return component(:prefix, raw, @prefix)
              end
            end
          end
          nil
        end

        # The next component from the back, or +nil+.
        def next_back
          until finished?
            case @back
            when STATES[:body]
              if @path.length > len_before_body
                size, component = parse_next_component_back
                @path = @path[0, @path.length - size].to_s
                return component if component
              else
                @back = STATES[:start_dir]
              end
            when STATES[:start_dir]
              @back = @std.windows? ? STATES[:prefix] : STATES[:done]
              if @has_physical_root
                @path = @path[0, @path.length - 1].to_s
                return component(:root_dir, @std.separator)
              elsif (prefix = @prefix)
                return component(:root_dir, @std.separator) if prefix.implicit_root? && !prefix.verbatim?
              elsif include_cur_dir?
                @path = @path[0, @path.length - 1].to_s
                return component(:cur_dir, ".")
              end
            else
              @back = STATES[:done]
              return component(:prefix, @path, @prefix) if prefix_len.positive?

              return nil
            end
          end
          nil
        end

        # What is left of the path, without the empty components at
        # either end that the body would skip, as Components::as_path.
        def as_path
          copy = dup
          copy.trim_left if @front == STATES[:body]
          copy.trim_right if @back == STATES[:body]
          copy.path
        end

        # Drops the empty components at the front, as trim_left does.
        def trim_left
          until @path.empty?
            size, component = parse_next_component
            return if component

            @path = @path[size..].to_s
          end
        end

        # Drops the empty components at the back, as trim_right does.
        def trim_right
          while @path.length > len_before_body
            size, component = parse_next_component_back
            return if component

            @path = @path[0, @path.length - size].to_s
          end
        end

        private def finished?
          @front == STATES[:done] || @back == STATES[:done] || @front > @back
        end

        private def len_before_body
          root = (@front <= STATES[:start_dir] && @has_physical_root) ? 1 : 0
          cur_dir = (@front <= STATES[:start_dir] && include_cur_dir?) ? 1 : 0
          prefix_remaining + root + cur_dir
        end

        private def separator?(char)
          prefix_verbatim? ? char == "\\" : @std.separator?(char)
        end

        private def include_cur_dir?
          return false if has_root?

          slice = @path[prefix_remaining..].to_s
          slice == "." || (slice.start_with?(".") && slice.length > 1 && separator?(slice[1].to_s))
        end

        private def parse_single_component(text)
          case text
          when "." then (@std.windows? && prefix_verbatim?) ? component(:cur_dir, ".") : nil
          when ".." then component(:parent_dir, "..")
          when "" then nil
          else component(:normal, text)
          end
        end

        private def parse_next_component
          index = @path.each_char.find_index { |char| separator?(char) }
          return [@path.length, parse_single_component(@path)] unless index

          [index + 1, parse_single_component(@path[0, index].to_s)]
        end

        private def parse_next_component_back
          rest = @path[len_before_body..].to_s
          index = rest.each_char.to_a.rindex { |char| separator?(char) }
          return [rest.length, parse_single_component(rest)] unless index

          text = rest[(index + 1)..].to_s
          [text.length + 1, parse_single_component(text)]
        end

        private def component(kind, text, prefix = nil)
          Component.new(kind:, as_os_str: text, prefix:)
        end
      end

      # The names Windows reserves for devices, which dunce never strips
      # a prefix from.
      RESERVED_NAMES = %w[
        AUX
        NUL
        PRN
        CON
        COM1
        COM2
        COM3
        COM4
        COM5
        COM6
        COM7
        COM8
        COM9
        LPT1
        LPT2
        LPT3
        LPT4
        LPT5
        LPT6
        LPT7
        LPT8
        LPT9
].freeze

      # Creates the rules for one family: Windows' when +windows+.
      def initialize(windows:)
        @windows = windows
        freeze
      end

      # Whether these are Windows' rules.
      def windows?
        @windows
      end

      # The main separator, Rust's MAIN_SEPARATOR_STR.
      def separator
        @windows ? "\\" : "/"
      end

      # Whether +char+ separates components: <tt>/</tt> everywhere, and
      # <tt>\\</tt> too on Windows.
      def separator?(char)
        char == "/" || (@windows && char == "\\")
      end

      # +path+'s components, from the front, as Path::components yields them.
      def components(path)
        Components.new(self, path).to_a
      end

      # Whether +path+ has a root, as Path::has_root.
      def has_root?(path)
        Components.new(self, path).has_root?
      end

      # Whether +path+ is absolute, as Path::is_absolute: a root on Unix,
      # and a root and a prefix on Windows.
      def absolute?(path)
        components = Components.new(self, path)
        @windows ? components.has_root? && !components.prefix.nil? : components.has_root?
      end

      # +path+ without its last component, as Path::parent, or +nil+ when
      # it ends in a root or a prefix, or is empty.
      def parent(path)
        components = Components.new(self, path)
        last = components.next_back
        return nil unless last && %i[normal cur_dir parent_dir].include?(last.kind)

        components.as_path
      end

      # +path+'s last component when it is a name, as Path::file_name.
      def file_name(path)
        last = Components.new(self, path).next_back
        return nil unless last && last.kind == :normal

        last.as_os_str
      end

      # The extension of +path+'s file name, as Path::extension.
      def extension(path)
        name = file_name(path)
        return nil unless name

        before, after = rsplit_file_at_dot(name)
        before && after
      end

      # +path+'s file name without its extension, as Path::file_stem.
      def file_stem(path)
        name = file_name(path)
        return nil unless name

        before, after = rsplit_file_at_dot(name)
        before || after
      end

      # +buf+ with +path+ pushed onto it, as PathBuf::push: an absolute
      # +path+, or on Windows one with a prefix, replaces +buf+; one with
      # only a root keeps +buf+'s prefix; a verbatim +buf+ takes
      # <tt>.</tt> and <tt>..</tt> away; and otherwise a separator joins
      # them unless +buf+ ends in one or is a bare drive.
      def push(buf, path)
        need_separator = !buf.empty? && !separator?(buf[-1].to_s)
        base = Components.new(self, buf)
        base_prefix = base.prefix
        if base.prefix_len.positive? && base.prefix_len == buf.length && base_prefix&.drive?
          need_separator = false
        end

        if absolute?(path) || !Components.new(self, path).prefix.nil?
          path.dup
        elsif base.prefix_verbatim? && !path.empty?
          push_verbatim(base.to_a, path)
        elsif has_root?(path)
          "#{buf[0, base.prefix_remaining]}#{path}"
        elsif need_separator
          "#{buf}#{separator}#{path}"
        else
          "#{buf}#{path}"
        end
      end

      # +path+ without a <tt>\\?\</tt> prefix where a legacy program could
      # open it the same, as dunce's simplified: a verbatim drive path
      # whose every component is a name Windows accepts and does not
      # reserve, no longer than 260. Off Windows, +path+ as it is.
      def simplified(path)
        safe_to_strip_unc?(path) ? path[4..].to_s : path
      end

      # The rules for +target+, a Utils::Platform::Target.
      def self.for(target)
        (target == Utils::Platform::Target::Windows) ? WINDOWS : UNIX
      end

      # +path+'s Windows prefix, as sys/path/windows_prefix.rs parses it,
      # or +nil+ (always on Unix).
      def parse_prefix(path)
        return nil unless @windows

        head = path[0, 8].to_s.tr("/", "\\")
        return disk_prefix(path) unless head.start_with?("\\\\")

        if head[2..].to_s.start_with?("?\\") && !path[0, 4].to_s.include?("/")
          verbatim_prefix(head, path)
        elsif head[2..].to_s.start_with?(".\\")
          Prefix.new(kind: :device_ns, parts: [next_component(path[4..].to_s, verbatim: false).first])
        else
          server, rest = next_component(path[2..].to_s, verbatim: false)
          share = next_component(rest, verbatim: false).first
          (server.empty? || share.empty?) ? nil : Prefix.new(kind: :unc, parts: [server, share])
        end
      end

      # Whether the first character after +prefix+ is a separator.
      def physical_root?(path, prefix)
        rest = prefix ? path[(prefix.len)..].to_s : path
        !rest.empty? && separator?(rest[0].to_s)
      end

      private def verbatim_prefix(head, path)
        if head[4..].to_s.start_with?("UNC\\")
          server, rest = next_component(path[8..].to_s, verbatim: true)
          share = next_component(rest, verbatim: true).first
          return Prefix.new(kind: :verbatim_unc, parts: [server, share])
        end

        rest = path[4..].to_s
        third = rest[2]
        drive = drive_letter(rest) if third.nil? || separator?(third)
        return Prefix.new(kind: :verbatim_disk, parts: [drive]) if drive

        Prefix.new(kind: :verbatim, parts: [next_component(rest, verbatim: true).first])
      end

      private def disk_prefix(path)
        drive = drive_letter(path)
        drive ? Prefix.new(kind: :disk, parts: [drive]) : nil
      end

      private def drive_letter(path)
        path.match?(/\A[A-Za-z]:/) ? path[0].to_s.upcase : nil
      end

      private def next_component(path, verbatim:)
        index = path.each_char.find_index { |char| verbatim ? char == "\\" : separator?(char) }
        index ? [path[0, index].to_s, path[(index + 1)..].to_s] : [path, ""]
      end

      private def push_verbatim(components, path)
        components(path).each do |component|
          case component.kind
          when :root_dir then components = [*components.first(1), component]
          when :cur_dir then nil
          when :parent_dir then components.pop if components.last&.kind == :normal
          else components << component
          end
        end
        joined = +""
        need_separator = false
        components.each do |component|
          joined << separator if need_separator && component.kind != :root_dir
          joined << component.as_os_str
          need_separator = case component.kind
          when :root_dir then false
          when :prefix
            prefix = component.prefix
            !prefix.nil? && !prefix.drive? && prefix.len.positive?
          else true
          end
        end
        joined
      end

      private def rsplit_file_at_dot(name)
        return [name, nil] if name == ".."

        index = name.rindex(".")
        return [nil, name] unless index

        before = name[0, index].to_s
        before.empty? ? [name, nil] : [before, name[(index + 1)..].to_s]
      end

      private def safe_to_strip_unc?(path)
        return false unless @windows

        first, *rest = components(path)
        return false unless first && first.kind == :prefix && first.prefix&.kind == :verbatim_disk

        rest.each do |component|
          case component.kind
          when :root_dir then next
          when :normal
            return false if !valid_filename?(component.as_os_str) || reserved?(component.as_os_str)
          else return false
          end
        end
        !(path.bytesize > 260 && windows_char_len(path) > 260)
      end

      private def windows_char_len(text)
        text.each_char.sum { |char| (char.ord <= 0xFFFF) ? 1 : 2 }
      end

      private def valid_filename?(name)
        return false if name.bytesize > 255 && windows_char_len(name) > 255
        return false if name.empty?
        return false if name.match?(%r{[\x00-\x1f<>:"/\\|?*]})

        !name.end_with?(" ", ".")
      end

      private def reserved?(name)
        stem = file_stem(name)
        return false unless stem

        trimmed = stem.sub(/[ .]+\z/, "")
        trimmed.bytesize <= 4 && RESERVED_NAMES.any? { |reserved| reserved.casecmp?(trimmed) }
      end

      # Unix's rules: <tt>/</tt> alone separates, and no path has a prefix.
      UNIX = new(windows: false)

      # Windows' rules: both separators, and drive, UNC, device, and
      # verbatim prefixes.
      WINDOWS = new(windows: true)
    end
  end
end

# SPDX-SnippetEnd
