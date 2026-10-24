# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "tmpdir"
require_relative "../../tasks/rbs_parity"

# A class defined outside the fixture library, which the library reopens.
class RbsParityReopened
end

# Tests the lint that keeps sig/ and lib/ describing the same methods.
#
# Each test writes a signature for a small fixture library and checks what
# the lint reports, so a rule that stops firing fails here.
class TestRbsParity < Minitest::Test
  LIB = Dir.mktmpdir("rbs_parity_lib")
  File.write(File.join(LIB, "fixture.rb"), <<~RUBY)
    module RbsParityFixture
      module Manager
        def app_handle
          raise NotImplementedError, "implement app_handle"
        end

        def config
          app_handle.config
        end
      end

      class Handle
        include Manager

        def initialize(name)
          @name = name
        end

        def app_handle
          self
        end

        def label
          @name
        end
        alias title label

        def rename(name, suffix = nil, upcase: false)
          @name = [name, suffix].compact.join
        end

        def self.build
          new("x")
        end

        protected def peer
          self
        end

        private def secret
          1
        end
      end

      module Helpers
        module_function

        def shout(text)
          text.upcase
        end
      end

      class Plugin
        def name
          "plugin"
        end
      end

      class Point < Data.define(:x, :y)
      end
    end

    class RbsParityReopened
      def added
        1
      end
    end
  RUBY
  load File.join(LIB, "fixture.rb")
  Minitest.after_run { FileUtils.remove_entry(LIB) }

  # Everything the fixture defines, declared faithfully.
  FAITHFUL = <<~RBS
    module RbsParityFixture
      module Manager
        def app_handle: () -> Handle
        def config: () -> String
      end

      class Handle
        include Manager
        def initialize: (String name) -> void
        def app_handle: () -> Handle
        def label: () -> String
        alias title label
        def rename: (String name, ?String? suffix, ?upcase: bool) -> String
        def self.build: () -> Handle
        def peer: () -> Handle

        private

        def secret: () -> Integer
      end

      module Helpers
        def self?.shout: (String text) -> String
      end

      interface _Plugin
        def name: () -> String
      end

      class Plugin
        include _Plugin
      end

      class Point < Data
        attr_reader x: Integer
        attr_reader y: Integer
        def self.new: (Integer x, Integer y) -> Point
                    | (x: Integer, y: Integer) -> Point
      end
    end

    class RbsParityReopened
      def added: () -> Integer
    end
  RBS

  private def violations(rbs, allowed: [], native_namespaces: [])
    Dir.mktmpdir do |sig|
      File.write(File.join(sig, "fixture.rbs"), rbs)
      RbsParity.new(sig_dirs: [sig], lib_dirs: [LIB], native_namespaces:, allowed:).violations
    end
  end

  # Loads +source+ into the fixture library for one test, then removes the
  # file and the constant so later tests do not see it.
  private def with_fixture(constant, source)
    path = File.join(LIB, "extra_#{name}.rb")
    File.write(path, source)
    load path
    yield
  ensure
    File.delete(path)
    RbsParityFixture.__send__(:remove_const, constant) if RbsParityFixture.const_defined?(constant, false)
  end

  def test_a_faithful_signature_passes
    assert_empty violations(FAITHFUL)
  end

  def test_a_declaration_only_an_ancestor_implements_is_flagged
    rbs = FAITHFUL.sub("def label: () -> String", "def label: () -> String\n    def config: () -> String")

    assert_equal [
"RbsParityFixture::Handle#config: declared in sig/ but only inherited from " \
  "RbsParityFixture::Manager; define it here or drop the declaration",
], violations(rbs)
  end

  def test_a_class_inheriting_a_stub_is_flagged_even_without_a_declaration
    with_fixture(:Stubbed, "class RbsParityFixture::Stubbed\n  include RbsParityFixture::Manager\nend\n") do
      rbs = "#{FAITHFUL}\nclass RbsParityFixture::Stubbed\n  include RbsParityFixture::Manager\nend\n"

      assert_equal [
"RbsParityFixture::Stubbed#app_handle: inherited from RbsParityFixture::Manager, whose " \
  "app_handle only raises NotImplementedError; define it here",
], violations(rbs)
    end
  end

  def test_a_declared_method_missing_from_lib_is_flagged
    rbs = FAITHFUL.sub("def label: () -> String", "def label: () -> String\n    def subtitle: () -> String")

    assert_equal ["RbsParityFixture::Handle#subtitle: declared in sig/ but not defined in lib/"], violations(rbs)
  end

  def test_a_declared_class_missing_from_lib_is_flagged
    rbs = "#{FAITHFUL}\nclass RbsParityGhost\nend\n"

    assert_equal ["RbsParityGhost: declared in sig/ but not defined in lib/"], violations(rbs)
  end

  def test_a_public_method_without_a_signature_is_flagged
    rbs = FAITHFUL.sub("    def label: () -> String\n", "")

    assert_equal ["RbsParityFixture::Handle#label: public in lib/ but has no signature"], violations(rbs)
  end

  def test_a_singleton_method_without_a_signature_is_flagged
    rbs = FAITHFUL.sub("    def self.build: () -> Handle\n", "")

    assert_equal ["RbsParityFixture::Handle.build: public in lib/ but has no signature"], violations(rbs)
  end

  def test_an_alias_needs_a_signature
    rbs = FAITHFUL.sub("    alias title label\n", "")

    assert_equal ["RbsParityFixture::Handle#title: public in lib/ but has no signature"], violations(rbs)
  end

  def test_a_declared_alias_must_exist
    rbs = FAITHFUL.sub("    alias title label\n", "    alias title label\n    alias heading label\n")

    assert_equal ["RbsParityFixture::Handle#heading: declared in sig/ but not defined in lib/"], violations(rbs)
  end

  def test_visibility_must_match
    rbs = FAITHFUL.sub("private\n", "")

    assert_equal ["RbsParityFixture::Handle#secret: public in sig/ but private in lib/"], violations(rbs)
  end

  def test_a_protected_method_may_only_be_declared_public
    rbs = FAITHFUL.sub("    def peer: () -> Handle\n", "    private def peer: () -> Handle\n")

    assert_equal ["RbsParityFixture::Handle#peer: private in sig/ but protected in lib/"], violations(rbs)
  end

  def test_a_private_method_declared_in_lib_need_not_be_signed
    rbs = FAITHFUL.sub("        def secret: () -> Integer\n", "")

    assert_empty violations(rbs)
  end

  def test_a_module_function_is_public_on_the_module_and_private_on_includers
    rbs = FAITHFUL.sub("def self?.shout:", "def shout:")

    assert_equal [
      "RbsParityFixture::Helpers#shout: public in sig/ but private in lib/",
      "RbsParityFixture::Helpers.shout: public in lib/ but has no signature",
], violations(rbs)
  end

  def test_an_included_interface_declares_its_methods
    rbs = FAITHFUL.sub("    def name: () -> String\n", "")

    assert_equal ["RbsParityFixture::Plugin#name: public in lib/ but has no signature"], violations(rbs)
  end

  def test_an_overload_passing_too_many_arguments_is_flagged
    rbs = FAITHFUL.sub("def label: () -> String", "def label: (Integer width) -> String")

    assert_equal [
"RbsParityFixture::Handle#label: overload (Integer width) passes arguments the implementation " \
  "does not accept",
], violations(rbs)
  end

  def test_an_overload_omitting_a_required_argument_is_flagged
    rbs = FAITHFUL.sub("def rename: (String name, ?String? suffix, ?upcase: bool)", "def rename: (?upcase: bool)")

    assert_equal 1, violations(rbs).grep(/Handle#rename: overload/).size
  end

  def test_an_overload_passing_an_unknown_keyword_is_flagged
    rbs = FAITHFUL.sub("?upcase: bool)", "?upcase: bool, ?trim: bool)")

    assert_equal 1, violations(rbs).grep(/Handle#rename: overload/).size
  end

  def test_initialize_arity_backs_self_new_on_a_plain_class
    rbs = FAITHFUL.sub("def initialize: (String name) -> void", "def initialize: () -> void")

    assert_equal [
"RbsParityFixture::Handle#initialize: overload () passes arguments the implementation " \
  "does not accept",
], violations(rbs)
  end

  def test_data_new_must_take_the_members
    rbs = FAITHFUL.sub("def self.new: (Integer x, Integer y) -> Point", "def self.new: (Integer x) -> Point")

    assert_equal ["RbsParityFixture::Point.new: overload (Integer x) does not match the Data members (x, y)"],
      violations(rbs)
  end

  def test_data_readers_must_be_declared
    rbs = FAITHFUL.sub("    attr_reader y: Integer\n", "")

    assert_equal ["RbsParityFixture::Point#y: public in lib/ but has no signature"], violations(rbs)
  end

  def test_initialize_on_a_data_class_is_flagged_even_beside_self_new
    rbs = FAITHFUL.sub("    attr_reader y: Integer\n", "    attr_reader y: Integer\n    def initialize: (x: Integer, y: Integer) -> void\n")

    assert_equal [
"RbsParityFixture::Point#initialize: declared on a Data class; declare self.new instead " \
  "(AGENTS.md)",
], violations(rbs)
  end

  def test_new_on_a_module_is_flagged
    rbs = FAITHFUL.sub("module Manager\n", "module Manager\n    def self.new: () -> Manager\n")

    assert_equal ["RbsParityFixture::Manager.new: declared in sig/ but not defined in lib/"], violations(rbs)
  end

  def test_new_on_a_plain_class_without_initialize_is_flagged
    with_fixture(:Bare, "class RbsParityFixture::Bare\nend\n") do
      rbs = "#{FAITHFUL}\nclass RbsParityFixture::Bare\n  def self.new: () -> RbsParityFixture::Bare\nend\n"

      assert_equal ["RbsParityFixture::Bare.new: declared in sig/ but neither new nor initialize is defined in lib/"],
        violations(rbs)
    end
  end

  def test_a_reopened_class_is_checked
    rbs = FAITHFUL.sub("  def added: () -> Integer\n", "")

    assert_equal ["RbsParityReopened#added: public in lib/ but has no signature"], violations(rbs)
  end

  # Comparable stands in for a native module: its constant has no Ruby
  # source location, so only a native namespace makes it ours.
  def test_a_native_namespace_makes_source_less_modules_ours
    assert_empty violations(FAITHFUL).grep(/\AComparable#/)
    assert_includes violations(FAITHFUL, native_namespaces: ["Comparable"]),
      "Comparable#between?: public in lib/ but has no signature"
  end

  def test_an_allowed_key_is_not_reported
    rbs = FAITHFUL.sub("    def label: () -> String\n", "")

    assert_empty violations(rbs, allowed: ["RbsParityFixture::Handle#label"])
  end
end
