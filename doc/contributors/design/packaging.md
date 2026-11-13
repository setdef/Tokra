<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Packaging Through Fledge

This document says what `tokra build` hands Fledge: the files it stages,
the packaged context, the `fledge.yml` it writes, what it does with each
key of Tauri's `bundle`, what each platform needs, and which Fledge
release it runs. It is for Tokra's contributors, and nothing in it is
built yet. Why things are so is in ADR 015 (the CLI, and packaging
through Fledge) and ADR 016 (development unless `tokra build` made it).
The commands themselves are in [cli.md](cli.md).

Tauri citations are to `vendor/tauri` at `9f0306fbc`. Fledge citations
are to its trunk at `fd4e6b45` (2026-11-12), and each capability names
the Fledge release that first shipped it.

## What Fledge promises

Fledge's interface is its command and the files it reads and writes
(Fledge ADR 029; its `doc/contributors/design/public-interface.md`,
"Frozen for 1.x" and "A framework wrapper's view"):

- `fledge build [-o DIR] [--sign IDENTITY | --sign-command COMMAND]
  [--notarize PROFILE] [PATH]`, exiting 0, 1 for a failed build, or 2
  for a usage error.
- One written path per line on standard output, and nothing else there.
- `fledge.yml`, whose schema (`lib/fledge/config.schema.json`) refuses any
  key it does not know.

Fledge's Ruby classes, its standard error's wording, and `fledge.cfg` are
not part of it. `tokra build` relies on nothing else.

Fledge ships the project whole: the nearest folder holding a `Gemfile`,
`gems.rb`, `fledge.yml`, or gemspec becomes the app's `app/` folder, less
`.git`, `.bundle`, `vendor/bundle`, `vendor/cache`, its output folders,
and any folder holding a `CACHEDIR.TAG`. It ships the gems of the groups
`bundle exec` would set up. It builds only for the computer it runs on
(Fledge ADR 010), and the app gets the runtime of the Ruby minor that runs
`fledge build` (Fledge ADR 055).

## What ships

A Tauri bundle carries the app's binary, with the frontend's assets and
the config compiled into it (`tauri-codegen/src/context.rs:184-196`); the
files `bundle.resources` names, copied into the resource folder by
`resource_relpath`, which writes `..` as `_up_`
(`tauri-bundler/src/bundle/settings.rs:1146-1153`,
`tauri-utils/src/resources.rs:17-24`); the `bundle.externalBin`
programs, copied beside the binary with their `-TARGET` suffix removed
(`settings.rs:1127-1143`); a `fixedRuntime` WebView2 folder, added to the
resources (`tauri-cli/src/interface/rust.rs:1434-1440`); and the icons,
desktop file, and platform files each installer writes
(`macos/app.rs:75-105`, `linux/debian.rs:115-140`). Nothing else from the
project reaches the user.

`tokra build` stages the same set, at the same relative paths, into
`.tokra/stage/`, which gets a `CACHEDIR.TAG` so neither Fledge nor a later
build ever ships `.tokra/`. Fledge's copy of the staged root then ships
exactly that:

- **The app, in place of the binary.** When the project root has a
  gemspec, the app is the files that gemspec lists, the gemspec,
  `Gemfile`, and `Gemfile.lock`. `tokra build` loads the gemspec in the
  developer's checkout, where its `files` expression runs as written
  (often `git ls-files`), and copies what it names. Without a gemspec the
  app is the config folder's tree, the counterpart of the crate beside
  `tauri.conf.json`, with `Gemfile` and `Gemfile.lock`, less `.tokra/`,
  every `node_modules`, the `frontendDist` folder (which ships as assets),
  and what Fledge never ships. A project that wants less writes a
  gemspec.
- **The config, compiled in.** The config files do not ship. The
  packaged context (below) takes their place, as Tauri's binary carries
  its config and reads no file.
- **The frontend's assets.** `tokra build` copies the `frontendDist`
  folder, or the files a `frontendDist` list names, into
  `tokra-packaged/assets/` beside the staged config. A `frontendDist` URL
  ships nothing, as in Tauri.
- **`bundle.resources`**, a list or a map, into
  `tokra-packaged/resources/` by Tauri's rules. The path resolver's
  `resource_dir`, which raises `NotImplementedError` until `tokra build`
  exists, answers that folder in a packaged app.
- **`bundle.externalBin`**, the host triple's file of each, into
  `tokra-packaged/bin/` with the suffix removed. The shell plugin's sidecar
  lookup, when it is ported, looks there in a packaged app. Fledge has not
  said that a shipped file keeps its executable bit; `rake test:package`
  checks it.
- **The icons**, under the names Fledge reads ("Icons", below), in
  `tokra-packaged/icons/`.

Files a Tauri plugin compiles into the binary, such as capabilities once
they are ported, ship inside the app by the same rule as its sources.

The staged project's Bundler settings add `development` to the
developer's own `without`. Fledge's trunk, after 0.12.0, ships the
`development` group unless `without` names it (its CHANGELOG,
Unreleased, Changed), and without this `tokra-cli`, Fledge, the dev
server, and the file watcher would ship in every app. A Cargo
dev-dependency never reaches a Tauri binary either.

Gems Fledge installs come from the lockfile, not from the developer's
computer. A path gem outside the project fails in the staged copy, as
Fledge refuses one already.

## The packaged context

`tokra build` writes `tokra.context.json` beside the staged config. It is
Tokra's counterpart of codegen's output: `dev` false, and the config as
`tokra build` merged it for this platform, `--config` patches included,
with `build.frontendDist` naming `tokra-packaged/assets/`. When the
Windows `webviewInstallMode` is `fixedRuntime`, it also names the staged
runtime folder.

`Tokra.generate_context` looks for the file in the folder it would read
the config from, before it looks for a config file. When it finds one it
builds the `Context` from it, with `dev` false, and reads no
`tokra.conf.json`. Otherwise it reads the config files as ADR 014 says,
with `dev` true, and merges the dev session ([cli.md](cli.md), "The dev
session"). The file exists only in the staged copy, never in the
developer's checkout.

`fledge build --sign` seals the file with the rest of the app. On macOS
codesign covers every file in the `.app` bundle, so removing or editing
it breaks the signature Gatekeeper checks. On Windows signtool signs
programs and libraries, so the signed setup program covers the file on
its way to the user but not once it is installed. Linux has no
signature. There the file is as tamper-resistant as the Ruby source
beside it.

## fledge.yml

`tokra build` writes `fledge.yml` at the staged root: `kind: windowed`,
the keys the table below maps, and `linux: system_libraries` ("Linux
libraries", below). It never writes `programs`, `ios`, `android`,
`build_tools`, or `windows: msix_*`: the app is one windowed program,
given as `fledge build`'s PATH, on the desktop.

A project with its own `fledge.yml` may name extra libraries under
`linux: system_libraries`, for gems other than Tokra's; `tokra build`
adds them to its own list. Any other key there is refused, naming it,
because the Tokra config owns it.

## Every key in Tauri's bundle

Each key takes one of these paths:

- **Mapped.** Fledge has it, and `tokra build` writes it into
  `fledge.yml`, onto Fledge's command line, or into the staged files.
- **Waiting.** Fledge plans it and has not shipped it, or has deferred
  it. `tokra build` refuses a config that sets the key away from Tauri's
  default for an installer this build produces, naming the key and the
  Fledge key or option it waits on, such as "`tokra.conf.json > bundle >
  category` needs Fledge's `linux: desktop_entry`, which Fledge 0.12.0
  lacks". When a Fledge release ships it and Tokra's pin moves, the key
  becomes mapped and the refusal goes.
- **Refused.** Fledge has declined it, or it cannot mean in a Ruby app
  what it means in Tauri. The table says why.

A key that Tauri reads only for an installer this build does not produce
is not refused, since `tauri build` would not use it either: `windows.wix`
without an MSI, `linux.rpm` without an RPM. A key left at Tauri's default
is not refused, but for the three defaults that ask for more than Fledge
has, which ADR 015 decides: `targets: "all"`, an unset `rank`, and an
unset `webviewInstallMode`.

| Tauri | Tauri writes it into | Tokra |
|---|---|---|
| `identifier` | every bundle | mapped to `identifier`. Fledge's pattern (two or more dot-separated parts, ASCII, at most 128 characters) is stricter than Tauri's check; Fledge's refusal is passed through |
| `productName` | every bundle | mapped to `name`; unset, Fledge's default (the gemspec's name, else the folder's, camelized) |
| `version` | every bundle | mapped to `version` |
| `bundle.active`, `bundle.targets`, `--bundles` | which bundles | mapped to `installers`: `dmg`, `nsis`, `appimage`, `deb` by name; `app` comes with every windowed macOS app; `active: false` without `--bundles` gives `[]`; `all` builds each of those the host can make, and prints each of Tauri's targets it left out (ADR 015). `rpm` waits for Fledge's `installers: [rpm]`, planned after its 1.0. `msi` waits for an MSI Fledge has deferred past its 1.0 with no plan |
| `bundle.publisher` | NSIS manufacturer, `.deb` `Maintainer` | mapped to `publisher` |
| `bundle.copyright` | `NSHumanReadableCopyright`, NSIS | mapped to `copyright` |
| `bundle.icon` | `.icns`, `.ico`, hicolor PNGs | mapped through `tokra-packaged/icons/` ("Icons") |
| `bundle.resources`, `bundle.externalBin` | resource folder, beside the binary | mapped by staging ("What ships") |
| `bundle.macOS.signingIdentity`, `bundle.windows.certificateThumbprint` | codesign, signtool | mapped to `--sign`, unless `--no-sign` |
| `bundle.windows.signCommand` | runs instead of signtool (`windows/sign.rs:135-192`) | mapped to `--sign-command` (Fledge 0.9.0), which then takes the place of `--sign`, as Tauri's command takes the thumbprint's. `tokra build` quotes each argument for `cmd.exe` and makes a relative path that exists absolute, as Tauri does. A command with no `%1` is refused: Fledge appends the path, where Tauri passes none |
| `bundle.homepage` | `.deb` `Homepage`, NSIS uninstall links, RPM | mapped to `homepage` (Fledge 0.6.0). Unset, the gemspec's `homepage`, as Tauri falls back to the Cargo package's (`settings.rs:1194-1200`). Fledge refuses anything but an http or https URL; its refusal is passed through |
| `bundle.shortDescription`, `bundle.longDescription` | `.deb` `Description`, desktop `Comment`, NSIS, RPM | mapped to `description` and `long_description` (Fledge 0.6.0). Unset, `description` is the gemspec's `summary`, as Tauri falls back to the Cargo package's description (`settings.rs:1219-1225`); Fledge has no default of its own |
| `bundle.category` | `LSApplicationCategoryType`, desktop `Categories` | waits for Fledge's `macos: info_plist` and `linux: desktop_entry`, planned for its 1.1.0. Tokra ports Tauri's category table and its "invalid category, did you mean" check (`tauri-bundler/src/bundle/category.rs:68-240`, `interface/rust.rs:1529-1534`) and writes each system's value; Fledge checks none |
| `bundle.licenseFile` | NSIS license page, disk image agreement, MSI | mapped to `license_file` (Fledge 0.6.0) for the Windows setup program. Not written on Linux, where Fledge would install it as the `.deb`'s copyright file and Tauri's `.deb` has none. A disk image's agreement waits for one Fledge has deferred past its 1.0, so a macOS build that makes a `dmg` refuses the key |
| `bundle.license` | RPM only (`linux/rpm.rs:61`) | with the RPM; no installer Fledge builds takes it, as none Tauri builds there does |
| `bundle.fileAssociations` | `CFBundleDocumentTypes`, NSIS registry, desktop `MimeType` | mapped to `file_associations` (Fledge 0.6.0): `ext` to `extensions`, `mimeType` to `mime_types`, `contentTypes` to `content_types`, `name`, and the `Editor` and `Viewer` roles. Fledge offers an app for its files and never makes it their default (Fledge ADR 052), so a `rank` set to anything but `Alternate`, a `Shell`, `QLGenerator`, or `None` role, a `description`, and an `exportedType` are refused. An unset `rank` is refused as `Default` is, naming `Alternate` (ADR 015). Opening the file is Tokra's side, and waits for the `Opened` run event |
| `bundle.createUpdaterArtifacts` | signed updater archives (`updater_bundle.rs`) | never in Fledge: an updater is the framework's role. `tokra build` ports `updater_bundle.rs` with the updater plugin; until then `true` and `"v1Compatible"` are refused |
| `bundle.useLocalToolsDir` | where tauri-bundler caches its tools | accepted with no effect: Fledge brings its own tools, and the key changes no output in Tauri either |
| `bundle.windows.digestAlgorithm` | signtool `/fd`, default `sha256` (`windows/sign.rs:19-25`) | `sha256` is accepted; any other value is refused: Fledge signs with SHA-256 only (`lib/fledge/windows_signing.rb:74`) |
| `bundle.windows.timestampUrl`, `tsp` | signtool `/t` or `/tr` | wait for Fledge's timestamp server, an environment variable planned after its 1.0. Fledge stamps with DigiCert's server (`windows_signing.rb:49`) |
| `bundle.windows.webviewInstallMode` | the NSIS WebView2 section | "Windows WebView2", below |
| `bundle.windows.allowDowngrades` | NSIS version check | `true`, the default, is what Fledge does. `false` waits for `windows: nsis_include` (Fledge 1.1.0), through which Tokra writes the check |
| `bundle.windows.nsis`'s `headerImage`, `sidebarImage`, `installerIcon`, `languages`, `customLanguageFiles`, `displayLanguageSelector`, and a `compression` other than `lzma` | NSIS | wait for `windows: nsis_include` (Fledge 1.1.0), through which Tokra writes the NSIS settings |
| `bundle.windows.nsis.minimumWebview2Version` | runs Microsoft's updater when older (`installer.nsi:584-606`) | waits for `windows: nsis_include` (Fledge 1.1.0): Tokra writes the version check with its WebView2 lines |
| `bundle.windows.nsis.installMode` | per user or per machine | `currentUser`, the default, is Fledge's. `perMachine` and `both` wait for a per-machine install Fledge has deferred past its 1.0, as a key of its own |
| `bundle.windows.nsis.startMenuFolder` | Start menu folder | waits for a Start menu folder Fledge has deferred past its 1.0 |
| `bundle.windows.nsis.template` | replaces the NSIS script | refused: Fledge's generated script is not its interface, and a template written for Tauri's names Tauri's variables |
| `bundle.windows.nsis.installerHooks` | developer NSIS at four points | refused: Fledge's include runs before the app is copied and nowhere else, so the hooks after install and at uninstall have no place |
| `bundle.windows.wix` | MSI only | with the MSI; not refused without one |
| `bundle.macOS.bundleVersion` | `CFBundleVersion` | mapped to `macos: build` (Fledge 0.6.0). Fledge takes one to three whole numbers between periods and refuses anything else; its refusal is passed through |
| `bundle.macOS.infoPlist` | merged over `Info.plist` (`macos/app.rs:422-432`) | waits for `macos: info_plist` (Fledge 1.1.0). Fledge's own keys win there, and a duplicate fails the build, where Tauri's file wins; such a key will be refused |
| `bundle.macOS.exceptionDomain` | ATS exception in `Info.plist` | waits for `macos: info_plist`, through which Tokra writes Tauri's `NSAppTransportSecurity` entry. WKWebView in the Ruby process reads ATS from the bundle's `Info.plist`, so it governs the app's web view |
| `bundle.macOS.minimumSystemVersion` | `LSMinimumSystemVersion`, default `10.13` | a value at or below 14.0, the default included, builds with Fledge's 14.0, the floor of its Ruby runtime, below which the app cannot run (`lib/fledge/platform.rb:56`). A higher value waits for `macos: info_plist`, which may raise it |
| `bundle.macOS.entitlements` | codesign | waits: Fledge signs with fixed entitlements (Fledge ADR 050) and plans a `macos: entitlements` fragment with its notarization story, unscheduled |
| `bundle.macOS.dmg` | disk image window and background | waits for disk image polish Fledge has deferred past its 1.0 |
| `bundle.macOS.frameworks`, `files` | the `.app` bundle | refused: Fledge declines extra files and frameworks in the bundle |
| `bundle.macOS.bundleName` | `CFBundleName` | refused unless it equals the name Fledge writes: Fledge declines a second name |
| `bundle.macOS.hardenedRuntime` | codesign | `true`, the default, is Fledge's. `false` is refused: Fledge signs the Ruby runtime with it, and notarization needs it |
| `bundle.macOS.providerShortName` | notarization | with notarization ("macOS", below) |
| `bundle.linux.appimage.bundleMediaFramework` | linuxdeploy's GStreamer plugin | `true` is refused: Fledge's AppImage is not built with linuxdeploy |
| `bundle.linux.appimage.files`, `bundle.linux.deb.files` | extra files at other system paths | refused: Fledge declines them, since its layout would become its interface |
| `bundle.linux.deb`'s `depends`, `recommends`, `provides`, `conflicts`, `replaces`, `priority`, `section` | `.deb` control fields | wait for `linux: deb_control` (Fledge 1.1.0). Fledge adds `Depends` entries after the ones it computes from `system_libraries` |
| `bundle.linux.deb.changelog` | `/usr/share/doc/PACKAGE/changelog.gz` | mapped to `linux: deb_changelog` (Fledge 0.6.0) |
| `bundle.linux.deb`'s `preInstallScript`, `postInstallScript`, `preRemoveScript`, `postRemoveScript` | maintainer scripts | wait for `linux: deb_scripts`, planned after Fledge's 1.0 |
| `bundle.linux.deb.desktopTemplate`, `bundle.linux.rpm.desktopTemplate` | replaces the desktop file | refused, as `nsis.template` is. Fledge's `linux: desktop_entry` merges lines and is not a template |
| `bundle.linux.rpm` | RPM only | with the RPM; not refused without one |
| `bundle.iOS`, `bundle.android` | mobile bundles | not read by `tauri build` for the desktop, nor by `tokra build` |

The deep-link plugin's desktop schemes also reach Tauri's installers
(`interface/rust.rs:866-871`). They wait for that plugin's port. Fledge
has no URL schemes yet.

## Linux libraries

Tokra's extension needs eleven libraries that Fledge's baseline,
auditwheel's manylinux_2_39 list (`lib/fledge/linkage.rb:77-80`), does
not cover. On an aarch64-linux build of Tokra's trunk (`readelf -d`,
2026-11-05) they are `libwebkit2gtk-4.1.so.0`, `libgtk-3.so.0`,
`libgdk-3.so.0`, `libsoup-3.0.so.0`, `libjavascriptcoregtk-4.1.so.0`,
`libgio-2.0.so.0`, `libgdk_pixbuf-2.0.so.0`, `libpango-1.0.so.0`,
`libcairo.so.2`, `libcairo-gobject.so.2`, and `libxdo.so.3` (muda's
`libxdo` feature). `libglib-2.0.so.0`, `libgobject-2.0.so.0`, and libc's
own libraries are in the baseline.

Fledge refuses a listed library that no gem needs, so the list is exact.
Tokra keeps it as a constant, and a Linux test compares it with the
built extension's `DT_NEEDED` entries less that baseline. Each Tokra
plugin that links a desktop library declares its own list the same way,
and `tokra build` writes the union for the plugins in the bundle.
libappindicator is opened with `dlopen` and cannot be listed (Fledge ADR
030, Consequences).

## Icons

Tauri sorts `bundle.icon` by kind and reads each PNG's pixel size.
Fledge reads no image: `icon` names a base path, and Fledge takes each
file by its name, `BASE.icns`, `BASE.ico`, and `BASE-16.png` through
`BASE-512.png` (Fledge ADR 048). `tokra build` writes `icon:
tokra-packaged/icons/app` and fills that folder:

- It reads each PNG's width and height from its header, as Tauri's Linux
  bundler does with a decoder (`linux/freedesktop/mod.rs:44-83`), and
  copies the first PNG of each size, in the list's order, to
  `app-SIZE.png`. A `@2x` file is named by its pixels, so
  `128x128@2x.png` becomes `app-256.png`; Tauri puts it in hicolor's
  `256x256@2` folder, which Fledge has no name for.
- The list's first `.ico` becomes `app.ico`, and a Windows build refuses
  a list without one, as `tauri-build` does.
- The first `.icns` becomes `app.icns`. With none, `tokra build` packs
  the PNGs into one as `create_icns_file` does, resizing a size that is
  not a power of two to the next one down (`macos/icon.rs:21-99`), with
  macOS's own `sips` and `iconutil`, since a macOS app builds only on a
  Mac.

A Linux build takes the sizes present, at least one of the six, and
Fledge names the missing ones on standard error (Fledge 0.6.0). A PNG of
a size outside the six is refused, naming it, since Tauri would ship it.
Fledge counts a new size a compatible addition, so Tokra asks for one
when an app needs it.

## Windows WebView2

Tauri's default `webviewInstallMode` is `downloadBootstrapper` with
`silent: true` (`tauri-utils/src/config.rs:980-984`), not `skip`, and its
NSIS installer acts on every mode (`windows/nsis/mod.rs:510-560`,
`installer.nsi:522-607`). Fledge's answer is `windows: nsis_include`
(planned for its 1.1.0): one NSIS script of the project's, included near
the top of Fledge's script and as a macro Fledge calls just before it
copies the app. Fledge keeps the install folder, the uninstall key, and
`RequestExecutionLevel user`, and ships nothing of Microsoft's.

Tokra writes that include once. It checks the `pv` value under
`EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}`, runs the
installer with `ExecWait` when the value is empty, and stops the install
with `Abort` when it fails, as Tauri's section does. The same include
carries the NSIS settings and the downgrade check from the table above.

| Mode | Tauri's installer | Tokra |
|---|---|---|
| `skip` | installs nothing | mapped: no WebView2 lines |
| `downloadBootstrapper` (default) | downloads Microsoft's bootstrapper at install time with NSISdl (`installer.nsi:538-551`) and runs it | waits for `nsis_include`. If Fledge's pinned NSIS carries NSISdl, the include downloads as Tauri's does; otherwise it embeds the bootstrapper, about 1.8 MB, which then downloads the runtime |
| `embedBootstrapper` | embeds the bootstrapper | waits for `nsis_include` |
| `offlineInstaller` | embeds the standalone installer, about 127 MB, for the target's architecture | waits for `nsis_include`, with the standalone installer for the host's architecture |
| `silent` | `/silent` before `/install` | with the mode it belongs to |
| `fixedRuntime` | ships the folder as a resource; the app sets `WEBVIEW2_BROWSER_EXECUTABLE_FOLDER` before its first web view (`crates/tauri/src/app.rs:2167-2185`) | mapped: staging ships the folder as a resource, and Tokra's runtime sets the variable from the packaged context. Like Tauri, Tokra does not grant the folder the permissions Microsoft asks for under Windows 10 from Fixed Version 120 |

Each Microsoft file comes from Microsoft's links at build time, as
Tauri's bundler fetches them (`WEBVIEW2_BOOTSTRAPPER_URL` and the offline
installer links, `tauri-bundler/src/bundle/windows/util.rs:13-17`,
fetched by `download_webview2_bootstrapper` and
`download_webview2_offline_installer`, `:42-55`), so no checksum is
pinned by hand and nothing of Microsoft's is republished.

## Windows signing

Fledge signs with the developer's `FLEDGE_SIGN_COMMAND` when its command
line gives neither `--sign` nor `--sign-command`. Tauri reads no such
variable, so `tokra build` runs Fledge without it, and an unsigned
config, or `--no-sign`, signs nothing, as in Tauri.

## macOS

Without `--sign`, Fledge signs ad hoc. With an identity it signs every
Mach-O file, the bundle, and the disk image, with the hardened runtime
and a timestamp.

Tauri notarizes the signed app when Apple's credentials are in the
environment (`APPLE_ID`, `APPLE_PASSWORD`, and `APPLE_TEAM_ID`, or
`APPLE_API_KEY`, `APPLE_API_ISSUER`, and `APPLE_API_KEY_PATH`;
`macos/sign.rs:96-120`), then staples the ticket unless
`--skip-stapling` (`macos/app.rs:124-139`). Fledge 0.9.0 added
`--notarize PROFILE`, which takes a `notarytool` keychain profile, not
credentials, and always staples (Fledge ADR 033). How Tauri's
credentials and `--skip-stapling` meet it is for the plan that ports
notarization. Until then `tokra build` refuses to build when those
credentials are set, naming them, since Tauri would notarize.

## The Fledge release

An app's `Gemfile` names Fledge from a release tag, in the `development`
group, as Fledge's README says:
`gem "fledge", git: "https://github.com/setdef/Fledge", tag: "vX.Y.Z", group: :development`.
Tokra's own `Gemfile` names the same tag for `rake test:package`. Tokra
names no Fledge yet; `tokra-cli`'s first plan chooses the release.

A gem cannot depend on a git source, and Fledge is not on RubyGems.org
before its 1.0.0, so `tokra-cli` does not declare Fledge. `tokra build`
runs `fledge --version` instead, and refuses any minor but the one it
knows, naming that one. Each new Fledge minor is a Tokra change, made
after reading Fledge's CHANGELOG. A minor that ships a capability turns
its waiting keys into mapped ones.

The app's Ruby is the Ruby that runs `tokra build`. Fledge 0.11 is its
last release with a Ruby 4.0 runtime; 0.12 and later run on Ruby 4.1
only, and refuse an older Ruby.

## What Fledge has

| Tokra needs | Fledge | State on Fledge's trunk |
|---|---|---|
| a description and a long description | `description`, `long_description` | released in 0.6.0 |
| a homepage | `homepage` | released in 0.6.0 |
| a license text | `license_file` | released in 0.6.0; a disk image's agreement deferred past 1.0 |
| a `.deb` changelog | `linux: deb_changelog` | released in 0.6.0 |
| the Linux icon sizes a developer has | no key | released in 0.6.0 |
| the files an app opens | `file_associations` | released in 0.6.0 |
| a macOS build number | `macos: build` | released in 0.6.0 |
| a Windows signing command | `--sign-command`, `FLEDGE_SIGN_COMMAND` | released in 0.9.0 |
| notarization | `--notarize PROFILE` | released in 0.9.0 |
| a category, ATS, a minimum macOS above 14.0, `.deb` control fields | `macos: info_plist`, `linux: desktop_entry`, `linux: deb_control` | planned for 1.1.0, not started |
| WebView2, refusing downgrades, the setup program's look | `windows: nsis_include` | planned for 1.1.0, not started |
| an RPM | `installers: [rpm]` | planned after 1.0, not started |
| a signing timestamp server | an environment variable | planned after 1.0, not started |
| `.deb` maintainer scripts | `linux: deb_scripts` | planned after 1.0, not started |
| entitlements | a `macos: entitlements` fragment | waits on Fledge's notarization story |
| an MSI; a per-machine install; a Start menu folder; a disk image's window, background, and agreement | none | deferred past 1.0, until a developer asks |
| extra files for a `.deb`, an AppImage, or the macOS bundle; frameworks; a bundle name; a whole NSIS or desktop file template | none | declined |
| URL schemes | none | not yet asked for |

Fledge's plan 003 holds the planned stories, and its CHANGELOG the
releases. Fledge's 1.0 waits for Ruby 4.1.0, among other things.

## Tests

Unit tests never run a real `fledge build`, which downloads a runtime
and compiles Tokra's extension. They cover every `bundle` key's path in
the table, each refusal message included; the staging tree, file by
file, with and without a gemspec, resources, and sidecars; the staged
Bundler settings; icon naming from real PNG headers; `fledge.yml`
checked against a copy of the pinned Fledge's schema; the command line
`tokra build` would run, with its environment; and `generate_context`
with and without a packaged context.

A `rake test:package` task, outside the default gate, runs the real
`tokra build` on the test app ([cli.md](cli.md), "Tests") with the
pinned Fledge. On Linux it also checks the library list and the `.deb`'s
`Depends`, and everywhere that a sidecar keeps its executable bit. CI
runs it on Linux under Xvfb, macOS, and Windows, then runs the built app,
which reports `dev` false. `rake test:linux` runs it in its container.
