<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

> Copied unchanged from Fledge's answer to Tokra, 2026-11-05, as research for [ADR 015](../adr/015.md). Its capability ids refer to [the companion note](2026-11-05-fledge-app-metadata-and-installer-needs.md).

# Tauri `bundle` keys against Fledge 0.5.1 (trunk dd11739), for Tokra's session

Not part of the Fledge repository (untracked scratch). Tokra owns this mapping. Fledge knows none of these key names; a "can" row names the neutral Fledge capability to request. Capability ids A1..C1 are in Fledge's `doc/contributors/research/2026-11-05-app-metadata-and-installer-needs.md` (sections 1 to 3); ids D1.. are listed after the table (short, not yet researched in depth, effort is a first estimate).

Status: **S** supported today; **C** Fledge can, does not yet; **N** never (or: not Fledge's role). Effort S/M/L as in that note. All "C" additions are compatible in 1.x (new key or new value, ADR 029 section 4) unless stated.

Sources: key list from `crates/tauri-utils/src/config.rs` at tauri `9f0306fbc` (BundleConfig 1287-1400, AppImageConfig 321, DebConfig 338, RpmConfig 437, DmgConfig 549, MacConfig 613, WixConfig 736, NsisConfig 847, WebviewInstallMode 943, WindowsConfig 1021, FileAssociation 1162, IosConfig 2847, AndroidConfig 2898); usage from `crates/tauri-bundler/src/bundle/**`, read in Tokra's local `vendor/tauri` checkout (not fetched). Fledge side from its code at dd11739.

Note on Tokra ADR 015, section 6 (Windows): Tauri's *default* `webviewInstallMode` is `downloadBootstrapper` with `silent: true` (`config.rs` `impl Default for WebviewInstallMode`, ~line 983), not `skip`. A config that leaves it unset therefore asks for the bootstrapper download, so "accepts `skip` and the unset default" treats the unset default as `skip`; a Windows 10 computer without the runtime then differs from `tauri build`'s result.

| Tauri key | Tauri's use (file) | Status | Fledge today / would be | Capability / effort |
|---|---|---|---|---|
| (top) `identifier`, `productName`, `version` | everywhere | S | `identifier`, `name`, `version` | none |
| `active` | gate in bundler | S | `installers: []` | none |
| `targets`: `app`, `dmg`, `nsis`, `appimage`, `deb` | `bundle/*` | S | `installers` values; `app` comes with a windowed macOS app | none |
| `targets`: `msi` | `windows/msi` (WiX) | C (L) | not built; a WiX path is a second Windows installer | D5, L, product scope |
| `targets`: `rpm` | `linux/rpm.rs` | C (L) | `rpmbuild` on Linux, like `dpkg-deb` (ADR 021) | D5, L |
| `targets`: `all` | | S | Tokra expands to the host's installers | none |
| `createUpdaterArtifacts` | `updater_bundle.rs` | N | no updater; a framework's role | none |
| `publisher` | NSIS manufacturer, deb Maintainer | S | `publisher` | none |
| `homepage` | deb Homepage (debian.rs:200), NSIS URLInfoAbout/HelpLink (installer.nsi:692-694), rpm url | C (S) | `homepage` | A2 |
| `icon` | mac icns, windows ico, linux PNGs by size | S with caveat | `icon` base path; Linux needs all six sizes today | C1 (S) makes sizes optional |
| `resources` | copied to resource dir | S | whole project ships as `app/`; Tokra stages files into the project and resolves paths in Ruby | none (Tokra) |
| `copyright` | plist NSHumanReadableCopyright (app.rs:406), NSIS | S | `copyright` | none |
| `license` | rpm only (rpm.rs:61) | C (S, little value) | no placement besides a deb copyright file | A4 (with the file) |
| `licenseFile` | NSIS page (installer.nsi:151), MSI, dmg agreement (dmg/mod.rs:161) | C (M; dmg L) | NSIS page and deb `copyright` file first | A4 |
| `category` | plist LSApplicationCategoryType (app.rs:256), desktop Categories (freedesktop/mod.rs:167) | C (S) | per-system raw values | A3; Tokra keeps its own category table (category.rs:149-240) |
| `fileAssociations` | plist CFBundleDocumentTypes (app.rs:316), NSIS registry (installer.nsi:640), desktop MimeType | C (M to L) | Fledge reserves `file_associations` (ADR 029 s.5, ADR 032 draft) | D4, M to L, maintainer's scope |
| `shortDescription` | deb Description, desktop Comment (mod.rs:171), NSIS/MSI | C (S to M) | `description` | A1 |
| `longDescription` | deb Description body (debian.rs:253), desktop template var, rpm | C (S to M) | `long_description` | A1 |
| `useLocalToolsDir` | tool cache location | N | Fledge brings its own tools | none |
| `externalBin` | sidecar binaries beside the executable, named per target | S with caveat | files in the project ship under `app/`; the executable bit and launch path are Tokra's; macOS signing covers every Mach-O file | none (Tokra); exec bit preservation unverified |
| `windows.digestAlgorithm` | signtool /fd | N | Fledge signs with SHA-256 always (`windows_signing.rb:73`) | none |
| `windows.certificateThumbprint` | signtool /sha1 | S | `--sign THUMBPRINT` | none |
| `windows.timestampUrl`, `windows.tsp` | signtool /t or /tr | C (S) | fixed DigiCert (`windows_signing.rb:48`) | D3, S |
| `windows.webviewInstallMode`: `skip` | writes nothing | S | no step | none |
| `…`: `downloadBootstrapper` (default) | NSISdl of fwlink at install (installer.nsi:538-551) | C (M to L) | not offered unpinned; embed it instead | B1 (embed a pinned file) |
| `…`: `embedBootstrapper` | bootstrapper in the setup program, `/silent /install` (installer.nsi:553-558, 574) | C (M to L) | a prerequisite entry with `file` or `url`+`sha256` | B1 |
| `…`: `offlineInstaller` | standalone installer embedded (~127 MB) | C (M to L) | the same entry with the big file | B1 |
| `…`: `fixedRuntime` | folder copied as a resource; env var set at run time (app.rs:2167-2185) | S mostly | ship the folder in the project; Tokra's Ruby sets the environment variable; Windows 10 needs `icacls` grants for v120+ (Microsoft), which has no home in Fledge | D2 (install-time command), M, not proposed |
| `…`: `silent` | `/silent` flag | C | the entry's `arguments` | B1 |
| `windows.allowDowngrades` | NSIS/MSI version check (installer.nsi:227, 260, 505) | C (S) | Fledge's installer always installs over | D6, S |
| `windows.wix.*` (version, upgradeCode, language, template, fragmentPaths, componentGroupRefs, componentRefs, featureGroupRefs, featureRefs, mergeRefs, enableElevatedUpdateTask, bannerPath, dialogImagePath, fipsCompliant) | MSI only | N while there is no MSI | no meaning without D5 | none |
| `windows.nsis.template` | custom .nsi | N | the generated script would become frozen API | none |
| `windows.nsis.headerImage`, `sidebarImage` | MUI bitmaps | C (S to M) | bitmaps `MUI_HEADERIMAGE`; no codec needed (BMP given by the developer) | D3 |
| `windows.nsis.installerIcon` | MUI_ICON | C (S) | Fledge uses the app's `.ico`; a separate one is a new key | D3 |
| `windows.nsis.installMode` | `currentUser` (default), `perMachine`, `both` | S for `currentUser`; C (L) for others | Fledge is per user only (ADR 009); per machine changes install paths, registry hive, elevation, frozen locations (ADR 029 s.2) | D7, L, product scope |
| `windows.nsis.languages`, `customLanguageFiles`, `displayLanguageSelector` | MUI languages | C (M) | English only today | D3 |
| `windows.nsis.compression` | SetCompressor | C (S) | LZMA solid fixed | D3 |
| `windows.nsis.startMenuFolder` | Start menu folder page | C (S to M) | shortcut at the Start menu root | D3 |
| `windows.nsis.installerHooks` | `.nsh` macros at four points | N | arbitrary script injection; B1 covers the one use that matters | none |
| `windows.nsis.minimumWebview2Version` | version compare, runs the component's updater (installer.nsi:584-606) | N (not proposed) | `installed_when` is presence, not version | none |
| `windows.signCommand` | custom signing tool | C (M) | `--sign` thumbprint with signtool only | D3 |
| `macOS.frameworks` | bundle .framework into Contents/Frameworks | C (M) | none; also signing order | D4 |
| `macOS.files` | files into Contents | C (S to M) | none; Fledge puts everything in Resources | D4 |
| `macOS.bundleVersion` | CFBundleVersion | C (S) | Fledge writes the version's first three numbers | D4 |
| `macOS.bundleName` | CFBundleName | C (S) | `name` | D4 |
| `macOS.minimumSystemVersion` | LSMinimumSystemVersion | N | the runtime's floor, macOS 14 (ADR 028/029 s.6): lowering would lie, raising is a major | none |
| `macOS.exceptionDomain` | ATS exception in plist | N | no meaning for a Ruby process's sockets | none |
| `macOS.signingIdentity` | codesign identity | S | `--sign IDENTITY` | none |
| `macOS.hardenedRuntime` | codesign option | S true; N false | always on (`mac_signing.rb:68`) | none |
| `macOS.providerShortName` | notarization | N | Fledge does not notarize | none |
| `macOS.entitlements` | codesign --entitlements | C (M) | fixed template for Ruby (`mac_signing.rb:50`) | D4 |
| `macOS.infoPlist` | merged into Info.plist (app.rs:422-432) | C (S to M) | `plutil` merge of a developer file | D4 |
| `macOS.dmg.*` (background, windowPosition, windowSize, appPosition, applicationFolderPosition) | create-dmg style | C (L) | Fledge's `dmg.rb` runs hdiutil without Finder scripting | D4, L |
| `linux.appimage.bundleMediaFramework` | gstreamer plugin | N | linuxdeploy-specific | none |
| `linux.appimage.files` | extra files into the AppDir | C (S to M) | none | D8 |
| `linux.deb.depends` | control Depends | C (S) | derived from `linux: system_libraries` plus libc6 | D8 (raw extra Depends) |
| `linux.deb.recommends`, `provides`, `conflicts`, `replaces` | control fields | C (S each) | none | D8 |
| `linux.deb.files` | extra files in the package | C (M) | none | D8 |
| `linux.deb.section` | control Section | C (S) | `Section: misc` | A3 |
| `linux.deb.priority` | control Priority | C (S) | `optional` | D8 |
| `linux.deb.changelog` | gzip to /usr/share/doc | C (S) | none | D8 |
| `linux.deb.desktopTemplate` | handlebars desktop file | N | template as API | none |
| `linux.deb.preInstallScript`, `postInstallScript`, `preRemoveScript`, `postRemoveScript` | maintainer scripts | C (S) | none; scripts run as root at install: maintainer's scope | D8 |
| `linux.rpm.*` (depends, recommends, provides, conflicts, obsoletes, release, epoch, files, desktopTemplate, the four scripts, compression) | rpm.rs | C (L) with D5, else N | no RPM | D5 |
| `iOS.template` | custom XcodeGen project.yml | S | `ios: host` replaces files | none |
| `iOS.frameworks`, `developmentTeam`, `infoPlist` | project settings | S via `ios: host` files (heavy) | edit `Host/Info.plist`, `project.yml` | none (Tokra: out of scope) |
| `iOS.bundleVersion` | CFBundleVersion | C (S) | reserved `ios: build` (ADR 029 s.5) | already reserved |
| `iOS.minimumSystemVersion` | deployment target | N | floor iOS 15; raising is a major | none |
| `android.minSdkVersion` | manifest | N | floor API 26 | none |
| `android.versionCode` | | C (S) | reserved `android: version_code` (ADR 029 s.5) | already reserved |
| `android.autoIncrementVersionCode` | read/modify a file | N | Tokra computes and passes `version_code` | none |

## Capability ids beyond the research note (first estimates only)

- D2. An install-time command on Windows (for example granting file permissions). M. Larger surface than B1; not proposed.
- D3. More Windows setup-program settings: signing timestamp server and custom sign command, installer images, installer icon, languages, compression, Start menu folder. Each S to M, one NSIS script line group plus a key. Independent; a wrapper picks which.
- D4. More macOS bundle settings: bundle version, bundle name, extra `Info.plist` keys from a file, entitlements, extra files and frameworks in the bundle, disk image window and background. S to L; `infoPlist` merge (S to M) covers most small needs.
- D5. A second installer format: an MSI (WiX) or an RPM (rpmbuild). L each, a pinned tool for MSI, ADR 021's pattern for RPM. Maintainer's product scope.
- D6. A setting that refuses an older version over a newer one in the Windows setup program. S.
- D7. A per-machine Windows installer (elevated, Program Files, HKLM). L, and changes frozen locations.
- D8. More `.deb` and AppImage settings: extra `Depends`, `Recommends`, `Provides`, `Conflicts`, `Replaces`, `Priority`, changelog, extra files, maintainer scripts. S each.
