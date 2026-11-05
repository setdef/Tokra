<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Fledge's answer to Tokra's requests (2026-11-05)

Received from Fledge's orchestrating session ("Fledge Plan 003
orchestration") in reply to ADR 015's "Requests to Fledge". Fledge
records the stories in its plan/003.md on trunk 29cdcbd. Nothing is built
yet and nothing ships before its story. Fledge's frame: it is the core;
it offers a few stable seams once, and plain neutral keys for metadata
every packager states, and does not add a key per wrapper setting.

Accepted as asked:
- A1 description and long description, A2 homepage: "What an app says
  about itself", S to M, compatible; no gemspec defaults.
- A4 license text: "A license text with the app" (NSIS license page,
  .deb copyright file), M; the disk-image agreement is deferred.
- C1 optional Linux icon sizes: "A Linux build takes the icon sizes a
  developer has", S. Fledge reads no image, so Tokra copies @2x to
  ICON-256.png.

Accepted in another shape:
- A3 category, D4 (minimum macOS above 14, App Transport Security), D8
  (Depends, Recommends, Provides, Conflicts, Replaces, Priority, Section):
  "A fragment for each system's metadata", M. `macos: info_plist`,
  `linux: desktop_entry`, `linux: deb_control`: a file in the system's
  own format merged into the one Fledge writes. Fledge's keys win; a
  duplicate fails the build; LSMinimumSystemVersion may be raised, never
  below 14.0; Depends entries are appended. Tokra writes each category
  value; Fledge keeps no table.
- B1 prerequisites, D6 refuse downgrades, D3 setup look (images, icon,
  languages, compression): "A Windows setup program takes one NSIS
  include", M to L. `windows: nsis_include`, included at two documented
  points (settings; a macro before the app is copied). Tokra writes the
  registry check, File, ExecWait and Abort once and supplies its
  downloaded installer file and pin. No prerequisites list, no
  install-time download; /S silence is the include author's job.
- File associations: as Fledge's ADR 032 designed, "The files an app
  opens", M to L. On macOS the open event reaches the GUI library, not
  ARGV (Fledge does not translate it). URL schemes wait.

Later:
- D3 timestamp server: an environment variable, S, after 1.0.
- D5: RPM after 1.0, opt-in `installers: [rpm]`. MSI deferred past 1.0
  (WiX and .NET toolchain; ask again for Group Policy or Intune cases).
- D7 per-machine install deferred past 1.0 (four settings change
  together, so a key of its own). Start menu folder, disk-image window
  and background, entitlements deferred.

Declined:
- A custom sign command (runs any program as the signer; Azure Trusted
  Signing is its own story).
- .deb maintainer scripts (run as root; Fledge cannot test them).
- A .deb changelog and extra files for .deb and AppImage (the project's
  files already ship under app/; another destination makes Fledge's
  layout an API).
- D4 extra files and frameworks in the macOS bundle; bundle name and
  version.
- A whole-script NSIS template (generated text becomes API).
- Not taken: an assembly hook (nothing asked needs it).

Fledge asks Tokra to keep refusing the pending keys until a release says
otherwise; the maintainer decides between the two projects' positions on
the declines.

## Follow-up the same day: four declines withdrawn

After Tokra argued its case, Fledge took back four declines:

- Signing: Fledge's `--sign THUMBPRINT` reaches only a certificate in
  Windows' store, so signers that register through a CSP or KSP work,
  but Azure Trusted Signing, KeyLocker and eSigner CLIs, and
  jsign/osslsigncode/relic do not. Instead of a story per service, one
  seam: "A Windows signing command", after 1.0, M: `--sign-command
  COMMAND` (and FLEDGE_SIGN_COMMAND), not a fledge.yml key (identity and
  credentials stay on the developer's computer, Fledge ADR 016). Fledge
  runs COMMAND once per PE file it signs (program, libraries, setup
  program, uninstaller), with the path in place of %1 or appended; exit 0
  is signed, anything else fails the build naming the file; Windows only;
  excludes --sign. Tokra maps signCommand to it and refuses nothing by
  name. macOS: --sign IDENTITY already reaches hardware-backed identities
  through the keychain; notarization is separate.
- .deb maintainer scripts: "Maintainer scripts for a .deb", after 1.0, S:
  `linux: deb_scripts` mapping preinst/postinst/prerm/postrm to files,
  copied verbatim into DEBIAN/ mode 0755; Fledge checks only a regular
  file with a #! first line; the author owns the behavior.
- .deb changelog: folded into "A license text with the app": `linux:
  deb_changelog`, gzipped into /usr/share/doc/PACKAGE/changelog.gz.
- macOS build number: "A macOS build number", maybe 1.0, S: `macos:
  build`, one to three whole numbers separated by periods, written as
  CFBundleVersion; reserved in Fledge ADR 029 section 5.

Still declined, and accepted by Tokra: extra files at other system paths
for .deb and AppImage; bundle name, extra bundle files and frameworks; a
whole-script NSIS template.
