# HydraBox Notices

HydraBox is an independent, unofficial derivative of
[Etonify](https://github.com/yamixdev/Etonify). HydraBox and its maintainers
do not claim authorship or ownership of the upstream work, and the HydraBox
name must not be interpreted as endorsement by or affiliation with Etonify,
MeowTeam, or the upstream developers.

The original Etonify work and notices are retained:

> Copyright 2026 MeowTeam.

HydraBox modifications are copyright 2026 HydraBox contributors. This tree
contains modifications to Etonify made on and after 2026-07-31; the Git history
records the relevant date and authorship of each change.

HydraBox, Etonify, and the source modifications in this repository are
distributed under the GNU General Public License v3.0 or later. The complete
license remains in [LICENSE](LICENSE). Third-party and adapted-source
attributions remain in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Exact upstream baselines and
compatibility identifiers are documented in [CREDITS.md](CREDITS.md).

## Private compatibility assets

An inherited encrypted Happ crypto compatibility archive may be present for
workflow compatibility. Its contents are not part of the readable public
source, and no permission to redistribute the archive or its decrypted
contents is implied by this repository's GPL license. The HydraBox release
workflow excludes those assets by default. A distributor must independently
verify that it has the necessary rights before restoring or shipping them.

APK obfuscation and minification can make casual repackaging harder, but they
do not make an APK or its bundled assets cryptographically secret.

## Original Etonify brand notice

The GPL controls copyright permissions for covered material; it does not by
itself grant trademark rights or a right to present an unrelated build as an
official Etonify release. The Etonify name and inherited visual identity must
only appear where the upstream origin is made truthful and unambiguous, unless
separate brand permission has been obtained. Package identities, release
channels, and update metadata must likewise not imply official status.

HydraBox's Flutter surfaces and Android, iOS, macOS, web, and Windows launcher
resources use the repository-native HydraBox mark; the inherited
`assets/images/logo.svg` is not shipped by this tree. The canonical source is
`assets/branding/hydrabox-logo.png`, and platform raster assets can be
reproduced without redrawing the mark with `tool/generate_hydrabox_icons.py`.

HydraBox uses its own application, package, storage, channel, deep-link, and
desktop identities. Etonify and MeowTeam names are retained only for accurate
source attribution and historical notices.
