# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "rbconfig"
require "rubygems/package"
require "stringio"

# Builds tokra's precompiled gem for the platform and Ruby it runs on, from
# the extension rake compile built (Plan 072).
#
# The source gem compiles the extension when it installs, which needs Rust,
# libclang, and on Linux WebKitGTK's development packages. A precompiled
# gem carries the compiled extension instead, as rake-compiler's native
# gems do: its platform is the build's, it has no extension to compile, and
# the extension sits where <tt>require "tokra/tokra"</tt> finds it, with
# the DLLs the build installs beside it (WebView2Loader.dll on Windows,
# ext/tokra/extconf.rb). Installing it copies files and runs nothing.
#
# It carries every file the source gem does, the crate and its lockfile
# among them, so the source of the extension it carries ships with it. It
# drops the source gem's rb_sys dependency, which only extconf.rb loads.
#
# Each platform builds its own gem, natively, on the Ruby it is for: the
# extension links the system's WebKitGTK and GTK on Linux and WebView2 on
# Windows, and a cross-compiler would need those platforms' libraries
# anyway.
class PlatformGem
  # Raised when the gem cannot be built; the message says why.
  class Failure < StandardError; end

  # The extension, without its file extension, relative to the gem.
  EXTENSION = "lib/tokra/tokra"

  # [root] The repository root.
  # [gemspec] The source gem's gemspec, relative to +root+.
  # [platform] The Gem::Platform the extension was built for.
  # [host_os] RbConfig's +host_os+, which says which C library a Linux
  #   Ruby runs on.
  # [ruby_version] The Ruby the extension was built for, as RubyGems sees
  #   it (Gem.ruby_version).
  # [dlext] The extension's file extension.
  # [extension] The extension, without its file extension, relative to the
  #   gem.
  def initialize(root:, gemspec: "tokra.gemspec", platform: Gem::Platform.local, host_os: RbConfig::CONFIG["host_os"],
    ruby_version: Gem.ruby_version, dlext: RbConfig::CONFIG["DLEXT"], extension: EXTENSION
  )
    @root = root
    @gemspec = gemspec
    @platform = platform
    @host_os = host_os
    @ruby_version = ruby_version
    @dlext = dlext
    @extension = extension
  end

  # The gem's platform. A Mac's has no darwin version: RubyGems installs an
  # <tt>arm64-darwin-24</tt> gem only on a Ruby that reports exactly darwin
  # 24, which names the build machine's macOS, not one the extension needs.
  # A Linux one names its C library: RubyGems matches a plain
  # <tt>x86_64-linux</tt> gem on musl too, where an extension built against
  # glibc does not load.
  def platform
    case @platform.os
    when "darwin" then Gem::Platform.new([@platform.cpu, "darwin", nil])
    when "linux" then Gem::Platform.new([@platform.cpu, "linux", @host_os.to_s.include?("musl") ? "musl" : "gnu"])
    else @platform
    end
  end

  # The gem's Ruby requirement: the source gem's, narrowed to the Ruby whose
  # ABI the extension was built for.
  #
  # A release's teeny versions keep its ABI, so a gem built on 4.1.2 serves
  # every 4.1, below the next minor's previews, as rake-compiler bounds its
  # native gems. A preview or a build of Ruby's master has an ABI version
  # of its own (include/ruby/internal/abi.h), and Ruby refuses an extension
  # built for another (dln.c, dln_load_and_init), so the gem is for exactly
  # that Ruby: 4.1.0.preview1, or 4.1.0.dev. Bundler then skips it on any
  # other Ruby and compiles the source gem instead.
  def required_ruby_version(source = source_spec.required_ruby_version)
    narrowed = if @ruby_version.prerelease?
      ["= #{@ruby_version}"]
    else
      major, minor = @ruby_version.segments
      [">= #{major}.#{minor}", "< #{major}.#{minor + 1}.dev"]
    end
    Gem::Requirement.new(*source.requirements.map { |op, version| "#{op} #{version}" }, *narrowed)
  end

  # The compiled files the gem carries, relative to the gem: the extension
  # and the DLLs beside it.
  def compiled
    extension = "#{@extension}.#{@dlext}"
    raise Failure, "#{extension} is missing; run rake compile first" unless File.file?(File.join(@root, extension))

    dlls = Dir.glob("*.dll", base: File.join(@root, File.dirname(@extension)))
    [extension, *dlls.sort.map { |dll| File.join(File.dirname(@extension), dll) }]
  end

  # The gem's specification: the source gem's, for this platform and Ruby,
  # with the compiled files and nothing to compile.
  def spec
    source_spec.dup.tap do |spec|
      spec.platform = platform
      spec.required_ruby_version = required_ruby_version(spec.required_ruby_version)
      spec.extensions = []
      spec.files = (spec.files + compiled).uniq
      spec.dependencies.reject! { |dependency| dependency.name == "rb_sys" }
    end
  end

  # Builds the gem into +dir+ and returns its path. A warning RubyGems
  # prints, such as for a file the gem lacks, fails the build.
  def build(dir)
    spec = self.spec
    FileUtils.mkdir_p(dir)
    output = File.join(File.expand_path(dir), spec.file_name)
    messages = StringIO.new
    Gem::DefaultUserInteraction.use_ui(Gem::StreamUI.new(StringIO.new, messages, messages, false)) do
      Dir.chdir(@root) { Gem::Package.build(spec, false, false, output) }
    end
    warnings = messages.string.lines.grep(/WARNING/)
    raise Failure, "#{spec.file_name} built with warnings:\n#{warnings.join}" if warnings.any?

    output
  rescue Gem::InvalidSpecificationException, Gem::Package::Error => e
    raise Failure, "#{spec&.file_name} did not build: #{e.message}\n#{messages&.string}"
  end

  private def source_spec
    Dir.chdir(@root) { Gem::Specification.load(File.join(@root, @gemspec)) } or
      raise Failure, "#{@gemspec} does not load"
  end
end
