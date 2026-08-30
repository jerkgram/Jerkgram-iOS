<p align="center"><a href="README.md">English</a> · <a href="README_RU.md">Русский</a></p>

<img src="assets/readme/hero.svg" alt="Jerkgram — Telegram, with more control." width="100%">

<p align="center">
  <a href="https://jerkgram.github.io/"><strong>Website</strong></a> ·
  <a href="https://github.com/jerkgram/Jerkgram-iOS/releases"><strong>Releases</strong></a> ·
  <a href="https://t.me/JerkgramApp"><strong>Stable channel</strong></a> ·
  <a href="https://t.me/JerkgramCommunity"><strong>Community</strong></a> ·
  <a href="docs/SOURCE_TRANSPARENCY.md"><strong>Source transparency</strong></a>
</p>

<p align="center">
  <img alt="iOS" src="https://img.shields.io/badge/iOS-client-111820?style=flat-square">
  <img alt="Telegram iOS 12.9.2" src="https://img.shields.io/badge/Telegram%20iOS-12.9.2-111820?style=flat-square">
  <img alt="GPL-2.0-or-later" src="https://img.shields.io/badge/license-GPL--2.0--or--later-111820?style=flat-square">
</p>

# Jerkgram

**Jerkgram is an independent alternative Telegram client for iOS focused on recovery, message context, customization and additional control.**

It keeps Telegram's native iOS experience as the foundation, then adds the missing layer: **what changed, what disappeared, and what still belongs to the conversation.**

> [!NOTE]
> Jerkgram is currently preparing its first Stable public-source release. Release-specific IPA hashes and source tags are intentionally not published until the final Stable artifact exists.

## Context survives

Jerkgram is designed around a simple idea: deleting or editing something on the server does not always need to erase all locally observed context.

- **Deleted message recovery** — preserve supported message context that Jerkgram already received.
- **Edit history** — inspect earlier locally observed states of edited messages.
- **Recovered replies** — preserve useful quote context around recovered messages.
- **Recovered media** — retain supported downloaded media and its surrounding context.
- **Time Machine** — inspect message changes and recovered history from one place.
- **Privacy controls** — additional control over read, typing and presence behavior.
- **Extended tools** — transcription, profile, media and power-user additions that build on Telegram's native architecture.

Feature availability is release-specific. The source tag and release notes for a Stable version are the authoritative description of that release.

## Built on Official Telegram for iOS

```text
Upstream repository   TelegramMessenger/Telegram-iOS
Upstream tag          release-12.9.2
Upstream commit       6ad963e5b62d354da79040f388ae2b9132fb17b8
```

Jerkgram is independent and is **not an official Telegram application**. It is intended to use its own Telegram API credentials and its own application/signing identity.

See [`UPSTREAM.md`](UPSTREAM.md) for the upstream relationship and comparison policy.

## See Jerkgram in action

The [Jerkgram website](https://jerkgram.github.io/) contains the current product story and real interface captures, including recovery before/after examples. Repository visuals stay intentionally release-safe rather than fabricating screenshots that may drift from the eventual Stable UI.

## Source transparency

<img src="assets/readme/provenance.svg" alt="Jerkgram release provenance: Official Telegram to exact Jerkgram source to Stable IPA and public source snapshot." width="100%">

For every Stable release, Jerkgram aims to make one thing unambiguous:

> **Which exact public source snapshot corresponds to this exact released IPA?**

A Stable release record binds together:

```text
Jerkgram version
Public source tag
Telegram upstream tag + commit
Stable IPA SHA-256
Source snapshot SHA-256
Source manifest
```

The public repository contains the **real final production source** corresponding to Stable releases. It is not a manually rewritten showcase copy of the app.

<img src="assets/readme/integrity.svg" alt="Source integrity principles: exact, verified and release-bound." width="100%">

Read the full contract in [`docs/SOURCE_TRANSPARENCY.md`](docs/SOURCE_TRANSPARENCY.md).

## Releases

Stable releases are distributed through both **[GitHub Releases](https://github.com/jerkgram/Jerkgram-iOS/releases)** and **[@JerkgramApp](https://t.me/JerkgramApp)**.

Each GitHub Stable release is the canonical release page for that version and is intended to contain the downloadable IPA, release notes, release provenance and links to the corresponding public source.

The Jerkgram website may link its **Download IPA** action directly to the IPA asset attached to the matching GitHub Release, while **View on GitHub** opens the full release page.

Beta testing, bug reports and feedback live in [@JerkgramCommunity](https://t.me/JerkgramCommunity).

See [`docs/RELEASES.md`](docs/RELEASES.md) for the release/source relationship and artifact naming.

## Building from source

The first Stable source snapshot will include release-verified build instructions for that exact tree.

Public source must not contain personal signing certificates, provisioning profiles, private keys, user sessions, tokens or private signing identities. Builders provide their own:

- Telegram `api_id` / `api_hash`;
- Apple signing identity;
- provisioning and bundle configuration.

See [`docs/BUILDING.md`](docs/BUILDING.md).

## Repository policy

The public repository is release-oriented. The source snapshot follows the actual materialized production tree rather than a separately beautified fork.

This means legacy filenames that are genuinely part of the production source are not silently renamed during export, while internal development-only material that is not part of the corresponding release source is kept separate.

## Contributing & support

- Bugs and reproducible runtime issues: [`CONTRIBUTING.md`](CONTRIBUTING.md)
- Security-sensitive issues: [`SECURITY.md`](SECURITY.md)
- General project support: [`SUPPORT.md`](SUPPORT.md)
- Community: [@JerkgramCommunity](https://t.me/JerkgramCommunity)

## License

Jerkgram is based on Telegram for iOS and is distributed under the **GNU General Public License, version 2 or later**, subject to the licenses of included third-party components.

See [`LICENSE`](LICENSE), [`UPSTREAM.md`](UPSTREAM.md), and [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

Jerkgram is an independent project and is not affiliated with, endorsed by, or produced by Telegram. Telegram is a trademark of its respective owner.

---

<p align="center"><strong>Jerkgram</strong><br><sub>Telegram, with more control.</sub></p>
