# Releases

## Distribution model

Jerkgram separates binary distribution from public source hosting.

- **Stable IPA announcements and distribution:** [@JerkgramApp](https://t.me/JerkgramApp)
- **Public Stable source:** `jerkgram/Jerkgram-iOS`
- **Beta discussion and feedback:** [@JerkgramCommunity](https://t.me/JerkgramCommunity)

GitHub hosts the public source and release provenance. It is not intended to become an uncontrolled IPA mirror.

## Stable release record

Each Stable release should publish or reference:

```text
Jerkgram version
Public source tag
Telegram upstream tag
Telegram upstream commit
Stable IPA SHA-256
Source archive SHA-256
Source manifest
```

## Naming

Recommended release naming:

```text
Git tag          v1.0.0
IPA              Jerkgram-1.0.0.ipa
Source archive   Jerkgram-1.0.0-source.zip
Manifest         SOURCE_MANIFEST.sha256
```

## Pre-release status

Until the first final Stable IPA exists, no release-specific SHA-256 or source tag is treated as canonical.
