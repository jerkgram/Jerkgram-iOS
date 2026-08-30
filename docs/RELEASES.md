# Releases

## Distribution model

Jerkgram uses GitHub Releases and Telegram as complementary official Stable distribution channels.

- **Canonical Stable release page and IPA asset:** [GitHub Releases](https://github.com/jerkgram/Jerkgram-iOS/releases)
- **Stable announcements and Telegram distribution:** [@JerkgramApp](https://t.me/JerkgramApp)
- **Public Stable source:** `jerkgram/Jerkgram-iOS`
- **Beta discussion and feedback:** [@JerkgramCommunity](https://t.me/JerkgramCommunity)

The GitHub Release for a Stable version is the canonical public release page for that version. It should contain or link to the Stable IPA, release notes, release provenance and the corresponding public source tag/snapshot.

The Jerkgram website may expose two separate actions:

- **Download IPA** — direct link to the IPA asset attached to the matching GitHub Release;
- **View on GitHub** — link to the full GitHub Release page.

Telegram remains an official release channel rather than a replacement for the GitHub release record.

## Stable release record

Each Stable release should publish or reference:

```text
Jerkgram version
Public source tag
Telegram upstream tag
Telegram upstream commit
Stable IPA filename
Stable IPA SHA-256
Source archive filename
Source archive SHA-256
Source manifest
Release notes
```

`JERKGRAM_RELEASE.json` is the machine-readable provenance record for the current Stable source snapshot.

## Naming

Recommended release naming:

```text
Git tag          v1.0.0
GitHub release   Jerkgram 1.0.0
IPA              Jerkgram-1.0.0.ipa
Source archive   Jerkgram-1.0.0-source.zip
Manifest         SOURCE_MANIFEST.sha256
```

The IPA asset name should stay predictable within a release so the website can link directly to it without presenting GitHub's release page as an intermediate download step.

## First Stable release checklist

Before a release is marked Stable:

1. freeze the exact final public source snapshot;
2. verify the source manifest;
3. compute the Stable IPA and source archive SHA-256 values;
4. complete `JERKGRAM_RELEASE.json`;
5. create the matching public source tag;
6. create the GitHub Release for that tag;
7. attach the Stable IPA and source artifacts;
8. publish release notes and provenance;
9. update the website download action to the exact GitHub Release IPA asset;
10. announce the same Stable version through [@JerkgramApp](https://t.me/JerkgramApp).

## Pre-release status

Until the first final Stable IPA exists, no release-specific SHA-256, source tag, download asset or release record is treated as canonical.
