# Stable Release Template

This document is the operator template for publishing a Jerkgram Stable release on GitHub.

Do not publish a release while any `<PLACEHOLDER>` value remains.

## Release identity

```text
Release title       Jerkgram <VERSION>
Git tag             v<VERSION>
IPA                  Jerkgram-<VERSION>.ipa
Source archive       Jerkgram-<VERSION>-source.zip
Manifest             SOURCE_MANIFEST.sha256
Upstream tag         release-12.9.2
Upstream commit      6ad963e5b62d354da79040f388ae2b9132fb17b8
```

The public source tag, `JERKGRAM_RELEASE.json`, uploaded artifacts and hashes must all describe the same Stable build.

## GitHub Release body

Copy the following into the GitHub Release and replace every placeholder with the final verified value.

~~~markdown
# Jerkgram <VERSION>

Jerkgram <VERSION> is a Stable release of Jerkgram for iOS.

> Jerkgram is an independent project based on Official Telegram for iOS. It is not an official Telegram application.

## Download

**IPA:** `Jerkgram-<VERSION>.ipa`

The IPA attached to this release is the canonical GitHub binary for this Stable version.

For release announcements and Telegram distribution, see [@JerkgramApp](https://t.me/JerkgramApp).

## Highlights

- <HIGHLIGHT_1>
- <HIGHLIGHT_2>
- <HIGHLIGHT_3>

See the source tag and release-specific notes for the authoritative contents of this version.

## Release provenance

| Field | Value |
| --- | --- |
| Jerkgram version | `<VERSION>` |
| Build number | `<BUILD_NUMBER>` |
| Public source tag | `v<VERSION>` |
| Telegram iOS upstream tag | `release-12.9.2` |
| Telegram iOS upstream commit | `6ad963e5b62d354da79040f388ae2b9132fb17b8` |
| IPA SHA-256 | `<IPA_SHA256>` |
| Source archive SHA-256 | `<SOURCE_ARCHIVE_SHA256>` |
| Source manifest SHA-256 | `<SOURCE_MANIFEST_SHA256>` |

## Source

The public source corresponding to this Stable release is the source tree at tag `v<VERSION>` in [`jerkgram/Jerkgram-iOS`](https://github.com/jerkgram/Jerkgram-iOS).

Release provenance is also recorded in [`JERKGRAM_RELEASE.json`](https://github.com/jerkgram/Jerkgram-iOS/blob/v<VERSION>/JERKGRAM_RELEASE.json).

## Installation

Installation depends on the signing method used on the target device. The release IPA is provided as-is for supported iOS sideloading/signing workflows.

## Feedback

- Stable announcements: [@JerkgramApp](https://t.me/JerkgramApp)
- Community, beta feedback and bug reports: [@JerkgramCommunity](https://t.me/JerkgramCommunity)

## License

Jerkgram is based on Telegram for iOS and is distributed under the GNU General Public License, version 2 or later, subject to the licenses of included third-party components.

See [`LICENSE`](https://github.com/jerkgram/Jerkgram-iOS/blob/v<VERSION>/LICENSE), [`UPSTREAM.md`](https://github.com/jerkgram/Jerkgram-iOS/blob/v<VERSION>/UPSTREAM.md), and [`THIRD_PARTY_NOTICES.md`](https://github.com/jerkgram/Jerkgram-iOS/blob/v<VERSION>/THIRD_PARTY_NOTICES.md).
~~~

## Final Stable checklist

### 1. Freeze the release

- [ ] Final Stable source tree is frozen.
- [ ] Final IPA was produced from that exact release tree.
- [ ] No release-blocking runtime issue remains.
- [ ] Jerkgram version and build number are final.
- [ ] Telegram upstream tag and commit are still `release-12.9.2` / `6ad963e5b62d354da79040f388ae2b9132fb17b8`.

### 2. Verify public source

- [ ] Public source snapshot contains the real corresponding production source.
- [ ] No private certificates, provisioning profiles, private keys, tokens, sessions or private credentials are present.
- [ ] Required third-party license and notice files are preserved.
- [ ] `docs/BUILDING.md` describes the actual Stable source tree and no longer contains pre-release-only wording.
- [ ] `JERKGRAM_RELEASE.json` has `status: "stable"` and contains the final version, build number, source tag and artifact hashes.
- [ ] `SOURCE_MANIFEST.sha256` is generated from the final public source snapshot.
- [ ] Source archive is generated and its SHA-256 is recorded.

### 3. Verify the IPA

- [ ] Final IPA filename is `Jerkgram-<VERSION>.ipa`.
- [ ] IPA installs and launches on the intended supported device/iOS range.
- [ ] Login and basic messaging work.
- [ ] Release-critical Jerkgram features have been smoke-tested.
- [ ] IPA SHA-256 is computed from the exact file that will be uploaded.
- [ ] Uploaded IPA is byte-identical to the verified Stable IPA.

### 4. Freeze Git history

- [ ] Final public source changes are committed to `main`.
- [ ] `main` points to the exact intended release source commit.
- [ ] Tag `v<VERSION>` is created on that exact commit.
- [ ] The tag resolves back to the expected commit before publishing the release.
- [ ] No placeholder release metadata remains in the tagged tree.

### 5. Prepare GitHub Release

- [ ] Create a **draft** GitHub Release for tag `v<VERSION>`.
- [ ] Release title is `Jerkgram <VERSION>`.
- [ ] Paste the release body from this template and replace every placeholder.
- [ ] Upload `Jerkgram-<VERSION>.ipa`.
- [ ] Upload `Jerkgram-<VERSION>-source.zip`.
- [ ] Upload `SOURCE_MANIFEST.sha256`.
- [ ] Confirm the displayed hashes match the locally verified values.
- [ ] Confirm all links in the release body resolve against `v<VERSION>`.
- [ ] Do not rely on GitHub's automatically generated “Source code” archives as the project provenance archive unless their exact hashes are intentionally recorded.

### 6. Final pre-publish verification

- [ ] Download the IPA back from the **draft** release and recompute SHA-256.
- [ ] Download the source archive back and recompute SHA-256.
- [ ] Verify both downloaded hashes still match `JERKGRAM_RELEASE.json`.
- [ ] Verify `JERKGRAM_RELEASE.json` validates against `docs/JERKGRAM_RELEASE.schema.json`.
- [ ] Verify the release page contains no `<PLACEHOLDER>` text.
- [ ] Verify there are no accidental internal/dev files in the tagged public tree.
- [ ] Extract and verify the exact final IPA metadata required by the AltStore source, including bundle identifier, version/build, minimum OS and complete app permissions; do not infer entitlements or privacy usage descriptions.
- [ ] Verify the release is not marked pre-release if this is the intended Stable.

### 7. Publish and distribute

- [ ] Publish the GitHub Release.
- [ ] Open the public release page in a logged-out/private browser session.
- [ ] Test the IPA asset download without GitHub authentication.
- [ ] Update `jerkgram.github.io/latest.json` with the exact Stable release metadata and canonical GitHub Release IPA asset.
- [ ] Update `jerkgram.github.io/altstore-source.json` from the verified final IPA metadata.
- [ ] Update the canonical block in `jerkgram.github.io/mirrors.json`; do not add unverified mirrors.
- [ ] Verify the website **Download IPA** action points to the exact GitHub Release IPA asset.
- [ ] Verify **View on GitHub** opens this release.
- [ ] Validate the AltStore source and test the same source URL in SideStore.
- [ ] Verify the website repository contains no `.ipa` copy.
- [ ] Verify `latest.json`, `JERKGRAM_RELEASE.json`, the GitHub Release, Telegram announcement and every verified mirror use the same IPA SHA-256.
- [ ] Publish the matching Stable announcement in [@JerkgramApp](https://t.me/JerkgramApp).
- [ ] Include the same version number and IPA SHA-256 in the Telegram announcement.
- [ ] Verify the website, GitHub and Telegram all point to the same Stable version.

### 8. After publication

- [ ] Keep the tagged source immutable.
- [ ] Do not replace the IPA asset silently. If the binary changes, publish a new release/version.
- [ ] Record any urgent known issue publicly rather than changing provenance behind the existing tag.
- [ ] If the release must be withdrawn, clearly mark it as withdrawn and remove download promotion from the website/Telegram without rewriting the released source history.
