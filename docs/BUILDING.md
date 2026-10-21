# Building Jerkgram from Source

This guide describes the public build contract for Jerkgram Stable source snapshots.

## Base

```text
TelegramMessenger/Telegram-iOS
release-13.0.0
f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838
```

## Stable source snapshot

The public Stable snapshot contains the release source tree and the corresponding build material included with that source, including the relevant Bazel/build definitions and source dependencies.

For Jerkgram 1.1.0, use the public source tag `v1.1.0` and verify the release metadata in `JERKGRAM_RELEASE.json` before building.

## What you provide yourself

You are expected to provide your own:

- Telegram `api_id` / `api_hash`;
- Apple signing identity;
- provisioning setup;
- bundle identifiers and Apple configuration appropriate to your build.

The public repository does not provide personal certificates, provisioning profiles, private keys, user sessions or private secrets.

## High-level flow

1. Check out the exact Stable source tag.
2. Verify `JERKGRAM_RELEASE.json` and `public-source-manifest.json`.
3. Configure your own Telegram API credentials and application identity.
4. Configure your own Apple signing environment.
5. Build using the build system included in the tagged release source tree.

## Build environment

Jerkgram keeps the Telegram for iOS build system that is present in the corresponding release source. Local signing, provisioning and developer-specific configuration are intentionally not published as part of the Stable source record.
