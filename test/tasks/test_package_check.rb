# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "tmpdir"
require_relative "../../tasks/package_check"

# Tests the packaging gate against throwaway gems in their own git
# repository, built and loaded with the real gem, git, and cargo commands.
class TestPackageCheck < Minitest::Test
  def setup
    @root = Dir.mktmpdir("package_check")
    write("fixture/fixture.gemspec", gemspec("fixture"))
    write("fixture/lib/fixture.rb", %(require_relative "fixture/part"\n))
    write("fixture/lib/fixture/part.rb", "module Fixture; PART = 42; end\n")
    # Compiled extensions are ignored as the repository ignores them: .bundle
    # on macOS, .so on Linux and Windows.
    write(".gitignore", "*.bundle\n*.so\n*.dll\nsecret.rb\ngenerated.txt\ntarget/\nCargo.lock.tmp\n")
    git("init", "--quiet")
    git("add", ".")
    @out = StringIO.new
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  private def gemspec(name, dependencies: [], extra: [])
    <<~RUBY
      Gem::Specification.new do |spec|
        spec.name = #{name.dump}
        spec.version = "0.0.1"
        spec.summary = "Fixture"
        spec.authors = ["Fixture"]
        spec.files = IO.popen(%w[git ls-files -z -- lib ext Cargo.toml Cargo.lock], chdir: __dir__, &:read)
          .split("\\x0") + #{extra.inspect}
        #{dependencies.map { |dep| "spec.add_dependency #{Array(dep).map(&:dump).join(', ')}" }.join("\n  ")}
      end
    RUBY
  end

  private def write(path, content)
    FileUtils.mkdir_p(File.dirname(File.join(@root, path)))
    File.write(File.join(@root, path), content)
  end

  private def git(*)
    system("git", *, chdir: @root, exception: true)
  end

  private def target(name: "fixture", smoke: %(require "fixture"\nputs Fixture::PART\n), packaged: ["lib"],
    generated: [], crate: nil, extension: nil
  )
    PackageCheck::Target.new(name:, dir: name, packaged:, generated:, crate:, extension:, smoke:)
  end

  private def check(*gems)
    PackageCheck.new(root: @root, gems: gems.empty? ? [target] : gems, out: @out).fast
  end

  def test_a_complete_package_passes_and_runs_its_smoke_script
    check

    assert_includes @out.string, "✅ fixture: 42"
  end

  def test_an_untracked_file_the_repository_loads_fails
    write("fixture/lib/fixture/new_part.rb", "module Fixture; NEW = 1; end\n")

    error = assert_raises(PackageCheck::Failure) { check }

    assert_includes error.message, "lacks files the repository loads"
    assert_includes error.message, "lib/fixture/new_part.rb"
  end

  def test_a_development_file_in_the_package_fails
    write("fixture/lib/notes.md", "draft\n")
    git("add", ".")

    error = assert_raises(PackageCheck::Failure) { check(target(packaged: ["lib/fixture.rb", "lib/fixture"])) }

    assert_includes error.message, "ships development files"
    assert_includes error.message, "lib/notes.md"
  end

  def test_a_generated_file_the_gemspec_forgets_fails
    write("fixture/lib/generated.txt", "made by a task\n")

    error = assert_raises(PackageCheck::Failure) { check(target(generated: ["lib/*.txt"])) }

    assert_includes error.message, "lib/generated.txt"
  end

  def test_a_generated_file_the_gemspec_adds_passes
    write("fixture/lib/generated.txt", "made by a task\n")
    write("fixture/fixture.gemspec", gemspec("fixture", extra: ["lib/generated.txt"]))

    check(target(generated: ["lib/*.txt"], smoke: %(puts File.read(File.join(ARGV[0], "lib/generated.txt")))))

    assert_includes @out.string, "made by a task"
  end

  def test_a_require_of_a_file_the_package_lacks_fails
    write("fixture/lib/fixture/extra.rb", %(require_relative "secret"\n))
    write("fixture/lib/fixture/secret.rb", "SECRET = 1\n")
    git("add", ".")

    error = assert_raises(PackageCheck::Failure) { check }

    assert_includes error.message, "cannot load such file"
  end

  def test_a_failing_smoke_script_fails
    error = assert_raises(PackageCheck::Failure) { check(target(smoke: %(require "fixture"\nabort "broken"\n))) }

    assert_includes error.message, "broken"
  end

  def test_the_smoke_script_cannot_see_the_repository
    smoke = %(require "fixture"\nrequire #{File.join(@root, 'fixture/lib/fixture/part.rb').dump}\n)

    error = assert_raises(PackageCheck::Failure) { check(target(smoke:)) }

    assert_includes error.message, "loaded from the repository instead of the package"
  end

  def test_a_gem_activated_without_being_declared_fails
    error = assert_raises(PackageCheck::Failure) { check(target(smoke: %(require "logger"\nputs Logger))) }

    assert_includes error.message, "fixture loaded logger, which it does not declare"
  end

  def test_a_declared_gem_may_be_activated
    write("fixture/fixture.gemspec", gemspec("fixture", dependencies: ["logger"]))

    check(target(smoke: %(require "logger"\nputs Logger)))

    assert_includes @out.string, "✅ fixture: Logger"
  end

  def test_a_gem_sees_only_the_gems_it_declares
    write("other/other.gemspec", gemspec("other"))
    write("other/lib/other.rb", %(require "fixture"\n))
    git("add", ".")
    other = target(name: "other", smoke: %(require "other"\nputs Fixture::PART\n))

    error = assert_raises(PackageCheck::Failure) { check(target, other) }

    assert_includes error.message, "cannot load such file -- fixture"
  end

  def test_a_gem_sees_the_gems_it_declares
    write("other/other.gemspec", gemspec("other", dependencies: ["fixture"]))
    write("other/lib/other.rb", %(require "fixture"\n))
    git("add", ".")

    check(target, target(name: "other", smoke: %(require "other"\nputs Fixture::PART\n)))

    assert_includes @out.string, "✅ other: 42"
  end

  def test_the_compiled_extension_is_copied_into_the_package
    write("fixture/lib/fixture/native.#{RbConfig::CONFIG['DLEXT']}", "compiled\n")
    smoke = %(puts File.read(File.join(ARGV[0], "lib/fixture/native.#{RbConfig::CONFIG['DLEXT']}")))

    check(target(extension: "lib/fixture/native", smoke:))

    assert_includes @out.string, "✅ fixture: compiled"
  end

  def test_a_missing_compiled_extension_fails
    error = assert_raises(PackageCheck::Failure) { check(target(extension: "lib/fixture/native")) }

    assert_includes error.message, "compile first"
  end

  private def write_crate(manifest_extra, dependencies: "")
    skip "cargo is not installed" unless system("cargo", "--version", out: File::NULL, err: File::NULL)

    write("fixture/Cargo.toml", %([workspace]\nmembers = ["ext/fixture"]\nresolver = "2"\n))
    manifest = "[package]\nname = \"fixture\"\nversion = \"0.1.0\"\nedition = \"2021\"\n#{dependencies}"
    write("fixture/ext/fixture/Cargo.toml", manifest)
    write("fixture/ext/fixture/src/lib.rs", "")
    system("cargo", "generate-lockfile", "--offline", chdir: File.join(@root, "fixture"), out: File::NULL,
      err: File::NULL, exception: true)
    # The lockfile comes from the valid manifest; the extra table lands after.
    write("fixture/ext/fixture/Cargo.toml", manifest + manifest_extra)
    git("add", ".")
  end

  def test_a_crate_that_resolves_alone_passes
    write_crate("")

    check(target(packaged: %w[lib ext Cargo.toml Cargo.lock], crate: "ext/fixture"))

    assert_includes @out.string, "ext/fixture resolves alone against the packaged Cargo.lock"
  end

  def test_a_crate_inheriting_from_a_missing_workspace_table_fails
    write_crate("\n[lints]\nworkspace = true\n")

    error = assert_raises(PackageCheck::Failure) do
      check(target(packaged: %w[lib ext Cargo.toml Cargo.lock], crate: "ext/fixture"))
    end

    assert_includes error.message, "cargo metadata"
  end

  # The two halves of rb_sys ship fixes separately, so the locked crate has
  # to satisfy the gem requirement the gemspec states.
  def test_a_locked_rb_sys_crate_outside_the_gem_requirement_fails
    write_crate("", dependencies: %(\n[dependencies]\nrb-sys = "0.9"\n))
    write("fixture/fixture.gemspec", gemspec("fixture", dependencies: [["rb_sys", "~> 0.9.900"]]))
    git("add", ".")

    error = assert_raises(PackageCheck::Failure) do
      check(target(packaged: %w[lib ext Cargo.toml Cargo.lock], crate: "ext/fixture"))
    end

    assert_match(/Cargo.lock pins rb-sys 0\.9\.\d+, but the gem requires rb_sys ~> 0\.9\.900/, error.message)
  end

  def test_unexpected_files_keeps_whole_path_segments
    gem = target(packaged: %w[lib LICENSE])

    assert_equal ["library/x.rb", "LICENSES/MIT.txt"],
      PackageCheck.unexpected_files(gem, ["lib/a.rb", "LICENSE", "library/x.rb", "LICENSES/MIT.txt"])
  end
end
