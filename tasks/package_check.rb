# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "rubygems/package"
require "tmpdir"

# Checks that each gem works once packaged, not just in the repository.
#
# The repository hides packaging mistakes. A file the gemspec forgets still
# loads from the working tree, and a crate that leans on the repository's
# Cargo workspace still compiles there. Both broke installed gems before
# (commit 1c098a3). This check builds each gem with gem build, then proves
# the package on its own: its files, its Cargo workspace and lockfile, and
# a smoke script that loads it in a fresh process that sees only the gem and
# the gems it declares.
#
# Fast mode (the default gate) unpacks each gem and loads it with the
# native extension the repository already compiled. Full mode installs the
# gems into an empty GEM_HOME, so RubyGems compiles every extension from the
# packaged sources (Plan 017).
#
# A dependency that RubyGems cannot install by name, because Bundler took it
# from a git source (ferro-arboard, ADR 011), comes from the bundle: fast
# mode puts its require paths on the load path, and full mode builds it from
# its checkout and installs it first.
#
# Files a gem reads without require (templates, assets) are checked only by
# what its smoke script exercises; the require-all script covers the rest.
class PackageCheck
  # One gem to check.
  #
  # [name] Gem name.
  # [dir] Directory holding the gemspec, relative to the repository.
  # [packaged] Paths the gem ships, relative to +dir+; anything else in the
  #   package is a development file that leaked in.
  # [generated] Globs of git-ignored files the gemspec adds by hand.
  # [crate] Path of the native crate inside the gem, or +nil+.
  # [extension] Path of the compiled extension inside the gem, without its
  #   file extension, or +nil+.
  # [smoke] Ruby source that exercises the gem. ARGV[0] is the gem's
  #   directory.
  class Target < Data.define(:name, :dir, :packaged, :generated, :crate, :extension, :smoke)
    # The gemspec file name.
    def gemspec
      "#{name}.gemspec"
    end

    # Path of the compiled extension inside the gem, or +nil+.
    def extension_file
      "#{extension}.#{RbConfig::CONFIG['DLEXT']}" if extension
    end
  end

  # Raised when a check fails; the message says what to fix.
  class Failure < StandardError; end

  # Unsets what Bundler and the repository put in a child's environment.
  UNBUNDLED = %w[BUNDLE_GEMFILE BUNDLE_BIN_PATH BUNDLER_SETUP BUNDLER_VERSION RUBYOPT RUBYLIB]
    .to_h { |name| [name, nil] }.freeze

  # Loads every Ruby file the package ships, so a require between packaged
  # files that names a file the package lacks fails here. ARGV[0] is the
  # gem's directory.
  REQUIRE_ALL = <<~RUBY
    spec_dir = ARGV.fetch(0)
    Dir.glob("lib/**/*.rb", base: spec_dir).sort.each do |file|
      next if file.end_with?("/version.rb")

      require File.join(spec_dir, file)
    end
  RUBY

  # Fails when a script reached past the package under test. ARGV holds the
  # gem directory, the repository root, the mode (+files+, +fast+, or
  # +full+), the gem name, the gems it may activate (itself and its runtime
  # dependencies, transitively, comma-separated), the names of every gem
  # this check builds, the directory holding those packages, and the
  # directories of bundled dependencies the script may load from even inside
  # the repository (comma-separated), as CI's vendor/bundle is.
  ISOLATED = <<~'RUBY'
    gem_dir, repo, mode, name, allowed, ours, packages, bundled = ARGV
    roots = [repo, File.realpath(repo)].map { |root| "#{root}/" }
    vendored = bundled.to_s.split(",").flat_map { |dir| [dir, File.realpath(dir)] }.map { |dir| "#{dir}/" }
    leaked = $LOADED_FEATURES.select { |feature| feature.start_with?(*roots) && !feature.start_with?(*vendored) }
    abort "loaded from the repository instead of the package: #{leaked.join(", ")}" if leaked.any?

    # Default gems ship with Ruby, so any app has them, even when a newer
    # copy of one is installed and activates instead.
    defaults = Gem::Specification.default_stubs.map(&:name)
    activated = Gem.loaded_specs.values.reject { |spec| spec.default_gem? || defaults.include?(spec.name) }
    undeclared = activated.map(&:name) - allowed.split(",")
    abort "#{name} loaded #{undeclared.join(", ")}, which it does not declare" if undeclared.any?

    built = [packages, File.realpath(packages)].map { |root| "#{root}/" }
    stray = activated.select { |spec| ours.split(",").include?(spec.name) }
      .reject { |spec| spec.full_gem_path.start_with?(*built) }
    abort "activated #{stray.map(&:full_gem_path).join(", ")} instead of the package under test" if stray.any?
    if mode == "full"
      loaded = Gem.loaded_specs[name]&.full_gem_path
      unless loaded && File.realpath(loaded) == File.realpath(gem_dir)
        abort "#{name} came from #{loaded.inspect}, not #{gem_dir}"
      end
    end
  RUBY

  # [root] The repository root.
  # [gems] The gems to check, in dependency order.
  # [out] Where progress goes.
  # [find_spec] Returns the installed or bundled Gem::Specification for a
  #   gem name, or +nil+.
  def initialize(root:, gems:, out: $stdout, find_spec: -> (name) { Gem::Specification.find_all_by_name(name).max_by(&:version) })
    @root = root
    @gems = gems
    @out = out
    @find_spec = find_spec
  end

  # Builds, unpacks, and smoke-tests each gem against the repository's
  # compiled extensions. Each script sees only its own gem's lib directory
  # and those of the gems it declares.
  def fast
    Dir.mktmpdir("tokra-package") do |work|
      packages = @gems.to_h { |gem| [gem.name, build(gem, work)] }
      unpacked = packages.transform_values { |package| unpack(package, work) }
      specs = packages.transform_values { |package| Gem::Package.new(package).spec }
      @gems.each do |gem|
        verify_files(gem, unpacked[gem.name])
        verify_crate(gem, unpacked[gem.name], specs[gem.name])
        copy_extension(gem, unpacked[gem.name])
      end
      env = isolated_env(File.join(work, "gems"))
      @gems.each do |gem|
        allowed = dependency_closure(gem.name, specs)
        libs = allowed.filter_map { |name| unpacked[name] }.map { |dir| File.join(dir, "lib") }
        bundled = bundled_dependencies(allowed, specs)
        libs += bundled.flat_map(&:full_require_paths)
        smoke(gem, env:, load_paths: libs, dir: unpacked[gem.name], mode: "fast", allowed:, work:,
          bundled: bundled.map(&:full_gem_path))
      end
    end
  end

  # Installs each gem into an empty GEM_HOME, compiling native extensions
  # from the packaged sources, then smoke-tests the installed gems.
  def full
    Dir.mktmpdir("tokra-package") do |work|
      home = File.join(work, "gems")
      packages = @gems.to_h { |gem| [gem.name, build(gem, work)] }
      specs = packages.transform_values { |package| Gem::Package.new(package).spec }
      @gems.each { |gem| verify_files(gem, unpack(packages[gem.name], work)) }
      env = isolated_env(home)
      bundled_dependencies(specs.keys.flat_map { |name| dependency_closure(name, specs) }.uniq, specs).each do |spec|
        package = build_bundled(spec, work)
        @out.puts "Installing #{File.basename(package)} from its bundled source (compiling)..."
        run!(env, Gem.ruby, "-S", "gem", "install", "--local", "--no-document", package, chdir: work)
      end
      packages.each_value do |package|
        @out.puts "Installing #{File.basename(package)} (compiling from the packaged sources)..."
        run!(env, Gem.ruby, "-S", "gem", "install", "--local", "--no-document", package, chdir: work)
      end
      @gems.each do |gem|
        dir = Dir.glob(File.join(home, "gems", "#{gem.name}-[0-9]*")).first
        raise Failure, "#{gem.name} did not install into #{home}" unless dir

        smoke(gem, env:, load_paths: [], dir:, mode: "full", allowed: dependency_closure(gem.name, specs), work:)
      end
    end
  end

  # Packaged paths that fall outside the gem's +packaged+ list.
  def self.unexpected_files(gem, contents)
    contents.reject do |path|
      gem.packaged.any? { |allowed| path == allowed || path.start_with?("#{allowed.chomp('/')}/") }
    end
  end

  # Working-tree files that the package lacks.
  def self.missing_files(working_tree, contents)
    working_tree - contents
  end

  # The dependencies among +names+ that RubyGems cannot install by name:
  # gems Bundler took from a git or path source, which leave no cached
  # package. Our own gems and default gems are never among them.
  private def bundled_dependencies(names, specs)
    names.reject { |name| specs.key?(name) }.filter_map { |name| @find_spec.call(name) }
      .reject { |spec| spec.default_gem? || File.exist?(spec.cache_file) }
  end

  # Builds a bundled dependency's package from its checkout.
  private def build_bundled(spec, work)
    output = File.join(work, "#{spec.full_name}.gem")
    gemspec = File.join(spec.full_gem_path, "#{spec.name}.gemspec")
    raise Failure, "#{spec.name}: no #{gemspec} to build it from" unless File.exist?(gemspec)

    run!(UNBUNDLED, Gem.ruby, "-S", "gem", "build", gemspec, "--output", output, chdir: spec.full_gem_path)
    output
  end

  private def build(gem, work)
    output = File.join(work, "#{gem.name}.gem")
    run!(UNBUNDLED, Gem.ruby, "-S", "gem", "build", gem.gemspec, "--output", output, chdir: File.join(@root, gem.dir))
    output
  end

  private def unpack(package, work)
    dir = File.join(work, "unpacked", File.basename(package, ".gem"))
    Gem::Package.new(package).extract_files(dir)
    dir
  end

  private def contents(dir)
    Dir.glob("**/*", File::FNM_DOTMATCH, base: dir).reject { |path| File.directory?(File.join(dir, path)) }
  end

  private def verify_files(gem, dir)
    packaged = contents(dir)
    unexpected = self.class.unexpected_files(gem, packaged)
    missing = self.class.missing_files(working_tree(gem), packaged)
    problems = []
    problems << "ships development files:\n#{list(unexpected)}" if unexpected.any?
    problems << "lacks files the repository loads (git add them, or add them to spec.files):\n#{list(missing)}" if missing.any?
    raise Failure, "#{gem.name} #{problems.join("\n")}" if problems.any?

    @out.puts "✅ #{gem.name}: #{packaged.size} files, none missing, no development files"
  end

  # Tracked and untracked (not ignored) files under the packaged paths, plus
  # the generated files the gemspec adds by hand. An untracked file is the
  # usual way to lose one: it loads from the working tree, but spec.files
  # comes from git ls-files.
  private def working_tree(gem)
    dir = File.join(@root, gem.dir)
    listed, status = Open3.capture2("git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--",
      *gem.packaged, chdir: dir)
    raise Failure, "git ls-files failed in #{dir}" unless status.success?

    files = listed.split("\x0").select { |path| File.file?(File.join(dir, path)) }
    files + gem.generated.flat_map { |pattern| Dir.glob(pattern, base: dir) }
  end

  # Resolves the packaged crate with Cargo on its own: no repository
  # workspace above it, no network, and no change to the shipped lockfile.
  # The locked rb-sys crate must also satisfy the gem's rb_sys requirement,
  # since the two halves of rb_sys ship fixes separately.
  private def verify_crate(gem, dir, spec)
    return unless gem.crate

    manifest = File.join(dir, gem.crate, "Cargo.toml")
    output = run!({}, "cargo", "metadata", "--format-version", "1", "--locked", "--offline", "--manifest-path",
      manifest, chdir: dir)
    metadata = JSON.parse(output)
    root = metadata.fetch("workspace_root")
    unless File.realpath(root) == File.realpath(dir)
      raise Failure, "#{gem.name}: the packaged crate resolved workspace #{root}, not the gem's own"
    end
    verify_rb_sys(gem, spec, metadata)

    @out.puts "✅ #{gem.name}: #{gem.crate} resolves alone against the packaged Cargo.lock"
  end

  private def verify_rb_sys(gem, spec, metadata)
    requirement = spec.runtime_dependencies.find { |dependency| dependency.name == "rb_sys" }&.requirement
    crate = metadata.fetch("packages").find { |package| package.fetch("name") == "rb-sys" }
    return unless requirement && crate
    return if requirement.satisfied_by?(Gem::Version.new(crate.fetch("version")))

    raise Failure, "#{gem.name}: Cargo.lock pins rb-sys #{crate.fetch('version')}, but the gem requires rb_sys " \
      "#{requirement}; run cargo update -p rb-sys --precise <a version that satisfies both>"
  end

  private def copy_extension(gem, dir)
    return unless gem.extension_file

    source = File.join(@root, gem.dir, gem.extension_file)
    raise Failure, "#{gem.name}: #{source} is missing; compile first" unless File.exist?(source)

    target = File.dirname(File.join(dir, gem.extension_file))
    FileUtils.mkdir_p(target)
    FileUtils.cp(source, File.join(dir, gem.extension_file))
    # The DLLs the build installs beside the extension, which it loads at
    # load time: WebView2Loader.dll on Windows (ext/tokra/extconf.rb).
    Dir.glob("*.dll", base: File.dirname(source)).each do |dll|
      FileUtils.cp(File.join(File.dirname(source), dll), target)
    end
  end

  # Runs the require-all script, then the gem's smoke script, each in a
  # process that sees only +load_paths+ and +env+.
  private def smoke(gem, env:, load_paths:, dir:, mode:, allowed:, work:, bundled: [])
    includes = load_paths.flat_map { |path| ["-I", path] }
    context = lambda do |run_mode|
      [dir, File.expand_path(@root), run_mode, gem.name, allowed.join(","), ours, work, bundled.join(",")]
    end
    run!(env, Gem.ruby, *includes, "-e", "#{REQUIRE_ALL}\n#{ISOLATED}", *context.call("files"), chdir: Dir.tmpdir)
    output = run!(env, Gem.ruby, *includes, "-e", "#{gem.smoke}\n#{ISOLATED}", *context.call(mode), chdir: Dir.tmpdir)
    @out.puts "✅ #{gem.name}: #{output.strip}"
  end

  private def ours
    @gems.map(&:name).join(",")
  end

  # The gem and its runtime dependencies, transitively: the gems a script
  # may activate. Built packages answer for our gems; installed specs for
  # the rest.
  private def dependency_closure(name, specs)
    seen = []
    queue = [name]
    until queue.empty?
      current = queue.shift
      next if seen.include?(current)

      seen << current
      spec = specs[current] || @find_spec.call(current)
      queue.concat(spec.runtime_dependencies.map(&:name)) if spec
    end
    seen
  end

  # An environment with no Bundler, no repository load path, and a GEM_HOME
  # of its own. GEM_PATH keeps Ruby's own gem directory for rb_sys and the
  # bundled gems (logger); the scripts reject any gem activated from it that
  # the gem under test does not declare.
  private def isolated_env(home)
    UNBUNDLED.merge("GEM_HOME" => home, "GEM_PATH" => [home, Gem.default_dir].join(File::PATH_SEPARATOR))
  end

  private def run!(env, *command, chdir:)
    output, status = Open3.capture2e(env, *command, chdir:)
    raise Failure, "#{command.join(' ')} failed in #{chdir}:\n#{output}" unless status.success?

    output
  end

  private def list(paths)
    paths.sort.map { |path| "  #{path}" }.join("\n")
  end
end
