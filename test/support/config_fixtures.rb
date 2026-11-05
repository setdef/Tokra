# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "tmpdir"

# What Tauri's own crates answered for each config fixture, and the
# helpers that hold Tokra's answers up against them (plan 054, "The
# fixture generator"). rake config:fixtures writes the answers from
# tauri-utils and tauri-codegen at vendor/tauri 9f0306fbc.
module ConfigFixtures
  ROOT = File.expand_path("../fixtures/config", __dir__)
  CASES = File.join(ROOT, "cases")
  FROM_VALUE = File.join(ROOT, "from_value")

  # The files a case holds that are not config files.
  CASE_FILES = %w[expected.jsonl parse_value.txt path.txt probes.txt].freeze

  # The target triple each answer names, as the target Tokra reads for.
  TARGETS = {
    "aarch64-apple-darwin" => Tokra::Utils::Platform::Target::MacOS,
    "x86_64-pc-windows-msvc" => Tokra::Utils::Platform::Target::Windows,
    "x86_64-unknown-linux-gnu" => Tokra::Utils::Platform::Target::Linux,
  }.freeze

  C = Tokra::Utils::Config

  # The from_value cases and their answers, by name.
  def self.from_value
    @from_value ||= begin
      cases = File.readlines(File.join(FROM_VALUE, "cases.jsonl"), chomp: true).reject(&:empty?)
        .to_h { |line| (row = Tokra::Ipc::Json.parse(line)).then { [row.fetch("name"), row] } }
      File.readlines(File.join(FROM_VALUE, "expected.jsonl"), chomp: true).reject(&:empty?).to_h do |line|
        answer = Tokra::Ipc::Json.parse(line)
        [answer.fetch("name"), cases.fetch(answer.fetch("name")).merge(answer)]
      end
    end
  end

  # The generator's build Tokra reads as: Tauri with its config-json5
  # feature and without config-toml, since Tokra reads JSON5 and TOML
  # waits on plan 054's question 2.
  BUILD = "json5"

  # The answers of BUILD for the config case +name+.
  def self.answers(name)
    File.readlines(File.join(CASES, name, "expected.jsonl"), chomp: true).reject(&:empty?)
      .map { |line| Tokra::Ipc::Json.parse(line) }.select { |answer| answer.fetch("build") == BUILD }
  end

  # The json5 cases, each with json5's answer merged in. Ruby's JSON reads
  # them, since some nest past the 128 levels Ipc::Json allows.
  def self.json5
    @json5 ||= begin
      dir = File.join(ROOT, "json5")
      read = -> (file) { File.readlines(File.join(dir, file), chomp: true).reject(&:empty?).map { |line| JSON.parse(line, max_nesting: false) } }
      cases = read.("cases.jsonl").to_h { |row| [row.fetch("name"), row] }
      read.("expected.jsonl").to_h { |answer| [answer.fetch("name"), cases.fetch(answer.fetch("name")).merge(answer)] }
    end
  end

  # The answer for +name+ on the platform these tests run on.
  def self.current_answer(name)
    answers(name).find { |answer| TARGETS.fetch(answer.fetch("target")) == Tokra::Utils::Platform::Target.current }
  end

  def self.case_names
    Dir.children(CASES).sort
  end

  # The JSON pointers the case +name+ probes.
  def self.probes(name)
    path = File.join(CASES, name, "probes.txt")
    File.exist?(path) ? File.readlines(path, chomp: true).map(&:strip).reject(&:empty?) : []
  end

  # Copies the config case +name+ into a new directory, by its real path,
  # yields the directory, and removes it.
  def self.with_case(name)
    Dir.mktmpdir("tokra-config-case") do |tmp|
      dir = File.realpath(tmp)
      Dir.children(File.join(CASES, name)).each do |entry|
        FileUtils.cp_r(File.join(CASES, name, entry), dir) unless CASE_FILES.include?(entry)
      end
      yield dir
    end
  end

  # +text+ with the generator's placeholders filled for +dir+: Tokra's
  # brand where Tauri's named a config file or the default title, and the
  # directory, with each path displayed as Tokra displays one.
  def self.fill(text, dir)
    text = text.gsub("{brand}", "tokra").gsub("{Brand}", "Tokra")
    text.gsub(%r{\{dir\}(/[^\s"`]*)?}) { C::Parse.display("#{dir}#{Regexp.last_match(1)}") }
  end

  # +value+, a JSON value, with #fill applied to every string in it.
  def self.fill_all(value, dir)
    case value
    when String then fill(value, dir)
    when Array then value.map { |item| fill_all(item, dir) }
    when Hash then value.transform_values { |item| fill_all(item, dir) }
    else value
    end
  end

  # +value+, a Tokra config value, as serde_json::to_value writes Tauri's,
  # so a test reads Tauri's probes through Tokra's accessors.
  def self.dump(value)
    case value
    when nil, true, false, Integer, Float, String then value
    when Pathname, Ferro::Url::Url then value.to_s
    when Array then value.map { |item| dump(item) }
    when Hash then value.to_h { |key, item| [key.to_s, dump(item)] }
    else dump_data(value)
    end
  end

  # The structs whose Rust types have skip_serializing_none, which leaves
  # a None field out instead of writing null.
  SKIP_NONE = [
    C::Config,
    C::AppConfig,
    C::WindowConfig,
    C::SecurityConfig,
    C::TrayIconConfig,
    C::BuildConfig,
    C::BundleConfig,
    C::LinuxConfig,
    C::DebConfig,
    C::RpmConfig,
    C::MacConfig,
    C::DmgConfig,
    C::IosConfig,
    C::AndroidConfig,
    Tokra::WindowEffectsConfig,
  ].freeze

  ENUMS = {
    Tokra::WebviewUrl::App => -> (value) { value.path.to_s },
    Tokra::WebviewUrl::External => -> (value) { value.url.to_s },
    Tokra::WebviewUrl::CustomProtocol => -> (value) { value.url.to_s },
    C::PreventOverflowConfig::Enable => lambda(&:enabled),
    C::PreventOverflowConfig::Margin => -> (value) { dump(value.margin) },
    C::Csp::Policy => lambda(&:policy),
    C::Csp::DirectiveMap => -> (value) { dump(value.directives) },
    C::CspDirectiveSources::Inline => lambda(&:sources),
    C::CspDirectiveSources::List => lambda(&:sources),
    C::DisabledCspModificationKind::Flag => lambda(&:flag),
    C::DisabledCspModificationKind::List => lambda(&:directives),
    C::FsScope::AllowedPaths => -> (value) { dump(value.paths) },
    C::FsScope::Scope => lambda do |value|
      {
"allow" => dump(value.allow),
"deny" => dump(value.deny),
"requireLiteralLeadingDot" => value.require_literal_leading_dot,
}
    end,
    C::HeaderSource::Inline => lambda(&:value),
    C::HeaderSource::List => lambda(&:values),
    C::HeaderSource::Map => lambda(&:values),
    C::CapabilityEntry::Reference => lambda(&:name),
    C::CapabilityEntry::Inlined => lambda(&:capability),
    C::PatternKind::Brownfield => -> (_value) { { "use" => "brownfield" } },
    C::PatternKind::Isolation => -> (value) { { "use" => "isolation", "options" => { "dir" => value.dir.to_s } } },
    C::FrontendDist::Url => -> (value) { value.url.to_s },
    C::FrontendDist::Directory => -> (value) { value.path.to_s },
    C::FrontendDist::Files => -> (value) { dump(value.paths) },
    C::BeforeDevCommand::Script => lambda(&:script),
    C::BeforeDevCommand::ScriptWithOptions => -> (value) { { "script" => value.script, "cwd" => value.cwd, "wait" => value.wait } },
    C::HookCommand::Script => lambda(&:script),
    C::HookCommand::ScriptWithOptions => -> (value) { { "script" => value.script, "cwd" => value.cwd } },
    C::RunnerConfig::String => lambda(&:cmd),
    C::RunnerConfig::Object => -> (value) { { "cmd" => value.cmd, "cwd" => value.cwd, "args" => value.args }.compact },
    C::BundleType => lambda(&:to_s),
    C::BundleTarget::All => -> (_value) { "all" },
    C::BundleTarget::List => -> (value) { dump(value.targets) },
    C::BundleTarget::One => -> (value) { value.target.to_s },
    C::V1Compatible => -> (value) { camel(value.name) },
    C::Updater::String => -> (value) { dump(value.compatible) },
    C::Updater::Bool => lambda(&:enabled),
    C::BundleResources::List => lambda(&:paths),
    C::BundleResources::Map => lambda(&:paths),
    C::BundleTypeRole => lambda(&:name),
    C::HandlerRank => lambda(&:name),
    C::NsisCompression => -> (value) { camel(value.name) },
    C::NSISInstallerMode => -> (value) { camel(value.name) },
    C::WixLanguage::One => lambda(&:language),
    C::WixLanguage::List => lambda(&:languages),
    C::WixLanguage::Localized => -> (value) { dump(value.languages) },
    C::WebviewInstallMode::Skip => -> (_value) { { "type" => "skip" } },
    C::WebviewInstallMode::DownloadBootstrapper => -> (value) { { "type" => "downloadBootstrapper", "silent" => value.silent } },
    C::WebviewInstallMode::EmbedBootstrapper => -> (value) { { "type" => "embedBootstrapper", "silent" => value.silent } },
    C::WebviewInstallMode::OfflineInstaller => -> (value) { { "type" => "offlineInstaller", "silent" => value.silent } },
    C::WebviewInstallMode::FixedRuntime => -> (value) { { "type" => "fixedRuntime", "path" => value.path.to_s } },
    C::CustomSignCommandConfig::Command => lambda(&:command),
    C::CustomSignCommandConfig::CommandWithOptions => -> (value) { { "cmd" => value.cmd, "args" => value.args } },
    C::RpmCompression::Gzip => -> (value) { { "type" => "gzip", "level" => value.level } },
    C::RpmCompression::Zstd => -> (value) { { "type" => "zstd", "level" => value.level } },
    C::RpmCompression::Xz => -> (value) { { "type" => "xz", "level" => value.level } },
    C::RpmCompression::Bzip2 => -> (value) { { "type" => "bzip2", "level" => value.level } },
    C::RpmCompression::None => -> (_value) { { "type" => "none" } },
    Tokra::Color => -> (value) { [value.red, value.green, value.blue, value.alpha] },
    Tokra::Theme => lambda(&:as_json),
    Tokra::TitleBarStyle => lambda(&:name),
    Tokra::BackgroundThrottlingPolicy => -> (value) { camel(value.name) },
    C::ScrollBarStyle => -> (value) { camel(value.name) },
    Tokra::Effect => -> (value) { camel(value.name) },
    Tokra::EffectState => -> (value) { camel(value.name) },
    Tokra::WindowEffectsConfig => lambda do |value|
      {
"effects" => dump(value.effects),
"state" => value.state && dump(value.state),
"radius" => value.radius,
"color" => value.color && dump(value.color),
}.compact
    end,
  }.freeze

  def self.dump_data(value)
    reader = ENUMS[value.class]
    return reader.call(value) if reader

    fields = value.class.const_get(:FIELDS).to_h { |field| [field.key, dump(value.public_send(field.member))] }
    SKIP_NONE.include?(value.class) ? fields.compact : fields
  end

  def self.camel(name)
    name.sub(/\A./, &:downcase)
  end

  # The value at the JSON pointer +pointer+ in +value+, or +nil+, as
  # serde_json's Value#pointer finds it.
  def self.pointer(value, pointer)
    pointer.split("/").drop(1).reduce(value) do |at, key|
      case at
      when Array then at[Integer(key, exception: false) || at.size]
      when Hash then at[key.gsub("~1", "/").gsub("~0", "~")]
      end
    end
  end

  # The values at +probes+ in +value+ dumped, as the generator wrote them.
  def self.probed(value, probes)
    dumped = dump(value)
    probes.to_h { |probe| [probe, pointer(dumped, probe)] }
  end
end
