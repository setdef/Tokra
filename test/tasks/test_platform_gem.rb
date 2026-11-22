# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "tmpdir"
require_relative "../../tasks/package_check"
require_relative "../../tasks/platform_gem"

# Tests the precompiled gem (Plan 072) against a throwaway gem in its own
# git repository, built with RubyGems and installed with the real gem
# command.
class TestPlatformGem < Minitest::Test
  def setup
    @root = Dir.mktmpdir("platform_gem")
    write("fixture.gemspec", <<~RUBY)
      Gem::Specification.new do |spec|
        spec.name = "fixture"
        spec.version = "0.0.1"
        spec.summary = "Fixture"
        spec.authors = ["Fixture"]
        spec.license = "MIT"
        spec.homepage = "https://example.com"
        spec.required_ruby_version = ">= 3.0"
        spec.files = IO.popen(%w[git ls-files -z -- lib ext], chdir: __dir__, &:read).split("\\x0")
        spec.extensions = ["ext/fixture/extconf.rb"]
        spec.add_dependency "rb_sys", "~> 0.9"
        spec.add_dependency "logger"
      end
    RUBY
    write("lib/fixture.rb", "module Fixture; PART = 42; end\n")
    write("ext/fixture/extconf.rb", "abort 'compiled'\n")
    write(".gitignore", "*.so\n*.dll\n")
    system("git", "init", "--quiet", chdir: @root, exception: true)
    system("git", "add", ".", chdir: @root, exception: true)
    @out = StringIO.new
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  private def write(path, content)
    FileUtils.mkdir_p(File.dirname(File.join(@root, path)))
    File.write(File.join(@root, path), content)
  end

  private def platform_gem(platform: "x86_64-linux", host_os: "linux-gnu", ruby_version: "4.1.0.preview1")
    PlatformGem.new(root: @root, gemspec: "fixture.gemspec", platform: Gem::Platform.new(platform), host_os:,
      ruby_version: Gem::Version.new(ruby_version), dlext: "so", extension: "lib/fixture/fixture")
  end

  def test_a_mac_gem_names_no_darwin_version
    assert_equal "arm64-darwin", platform_gem(platform: "arm64-darwin-24", host_os: "darwin24").platform.to_s
  end

  def test_a_linux_gem_names_glibc
    assert_equal "x86_64-linux-gnu", platform_gem(platform: "x86_64-linux", host_os: "linux-gnu").platform.to_s
    assert_equal "aarch64-linux-gnu", platform_gem(platform: "aarch64-linux", host_os: "linux").platform.to_s
  end

  def test_a_linux_gem_built_on_musl_names_musl
    assert_equal "x86_64-linux-musl", platform_gem(platform: "x86_64-linux-musl", host_os: "linux-musl").platform.to_s
  end

  def test_a_windows_gem_keeps_ruby_s_platform
    assert_equal "x64-mingw-ucrt", platform_gem(platform: "x64-mingw-ucrt", host_os: "mingw32").platform.to_s
  end

  def test_a_gem_built_on_a_preview_serves_only_that_preview
    requirement = platform_gem(ruby_version: "4.1.0.preview1").required_ruby_version

    assert requirement.satisfied_by?(Gem::Version.new("4.1.0.preview1"))
    %w[4.1.0.preview2 4.1.0.dev 4.1.0 4.0.9].each do |other|
      refute requirement.satisfied_by?(Gem::Version.new(other)), "#{requirement} admits #{other}"
    end
  end

  def test_a_gem_built_on_ruby_s_master_serves_only_master
    requirement = platform_gem(ruby_version: "4.1.0.dev").required_ruby_version

    assert requirement.satisfied_by?(Gem::Version.new("4.1.0.dev"))
    refute requirement.satisfied_by?(Gem::Version.new("4.1.0.preview1"))
    refute requirement.satisfied_by?(Gem::Version.new("4.1.0"))
  end

  def test_a_gem_built_on_a_release_serves_its_minor_version
    requirement = platform_gem(ruby_version: "4.1.2").required_ruby_version

    %w[4.1.0 4.1.2 4.1.9].each { |version| assert requirement.satisfied_by?(Gem::Version.new(version)), version }
    %w[4.1.0.preview1 4.2.0.preview1 4.2.0 4.0.9].each do |other|
      refute requirement.satisfied_by?(Gem::Version.new(other)), "#{requirement} admits #{other}"
    end
  end

  def test_the_requirement_keeps_the_source_gem_s_floor
    requirement = platform_gem(ruby_version: "4.1.0").required_ruby_version(Gem::Requirement.new(">= 4.1.1"))

    refute requirement.satisfied_by?(Gem::Version.new("4.1.0"))
    assert requirement.satisfied_by?(Gem::Version.new("4.1.1"))
  end

  def test_the_gem_carries_the_extension_and_its_dlls_with_nothing_to_compile
    write("lib/fixture/fixture.so", "compiled")
    write("lib/fixture/Loader.dll", "dll")
    spec = Gem::Package.new(platform_gem.build(File.join(@root, "pkg"))).spec

    assert_equal "x86_64-linux-gnu", spec.platform.to_s
    assert_empty spec.extensions
    assert_includes spec.files, "lib/fixture/fixture.so"
    assert_includes spec.files, "lib/fixture/Loader.dll"
    assert_includes spec.files, "ext/fixture/extconf.rb"
    assert_equal ["logger"], spec.runtime_dependencies.map(&:name)
    assert_equal Gem::Requirement.new(">= 3.0", "= 4.1.0.preview1"), spec.required_ruby_version
  end

  def test_a_gem_without_its_extension_does_not_build
    error = assert_raises(PlatformGem::Failure) { platform_gem.build(File.join(@root, "pkg")) }

    assert_match "lib/fixture/fixture.so is missing", error.message
  end

  def test_a_gem_that_builds_with_warnings_does_not_build
    write("lib/fixture/fixture.so", "compiled")
    File.write(File.join(@root, "fixture.gemspec"), File.read(File.join(@root, "fixture.gemspec")).sub(/^.*homepage.*\n/, ""))

    error = assert_raises(PlatformGem::Failure) { platform_gem.build(File.join(@root, "pkg")) }

    assert_match "no homepage specified", error.message
  end

  private def target
    PackageCheck::Target.new(name: "fixture", dir: ".", packaged: %w[lib ext], generated: [], crate: nil,
      extension: "lib/fixture/fixture", smoke: %(require "fixture"\nputs "part \#{Fixture::PART}"\n))
  end

  # A gem for this platform and Ruby, so RubyGems installs it here.
  private def local_gem
    write("lib/fixture/fixture.#{RbConfig::CONFIG['DLEXT']}", "compiled")
    PlatformGem.new(root: @root, gemspec: "fixture.gemspec", extension: "lib/fixture/fixture")
      .build(File.join(@root, "pkg"))
  end

  def test_a_precompiled_gem_installs_and_runs_its_smoke_script
    PackageCheck.new(root: @root, gems: [target], out: @out).precompiled(target, local_gem)

    assert_includes @out.string, "✅ fixture-0.0.1-"
    assert_includes @out.string, "✅ fixture: part 42"
  end

  def test_a_gem_with_an_extension_to_compile_is_refused
    package = File.join(@root, "fixture-0.0.1.gem")
    system("gem", "build", "fixture.gemspec", "--output", package, chdir: @root, out: File::NULL, err: File::NULL,
      exception: true)

    error = assert_raises(PackageCheck::Failure) do
      PackageCheck.new(root: @root, gems: [target], out: @out).precompiled(target, package)
    end

    assert_match "is for every platform", error.message
    assert_match "has extensions to compile: ext/fixture/extconf.rb", error.message
    assert_match "lacks its compiled extension, lib/fixture/fixture", error.message
  end

  def test_the_install_path_holds_no_rust_toolchain
    with_rust = File.join(@root, "rust")
    without = File.join(@root, "plain")
    write("rust/cargo", "")
    write("plain/ruby", "")

    assert_equal without, PackageCheck.path_without_rust([with_rust, without].join(File::PATH_SEPARATOR))
  end
end
