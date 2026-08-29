# Building Jerkgram from Source

> [!NOTE]
> This guide defines the public build contract before the first Stable snapshot. Exact release commands will be frozen and verified against that snapshot before publication.

## Base

```text
TelegramMessenger/Telegram-iOS
release-12.9.2
6ad963e5b62d354da79040f388ae2b9132fb17b8
```

## What a Stable public snapshot includes

The public snapshot is intended to include the production code and corresponding build material required for that released tree, including relevant Bazel/build definitions and source dependencies that are part of the release source.

## What you provide yourself

You are expected to provide your own:

- Telegram `api_id` / `api_hash`;
- Apple signing identity;
- provisioning setup;
- bundle identifiers and Apple configuration appropriate to your build.

The public repository does not provide personal certificates, provisioning profiles, private keys, user sessions or private secrets.

## High-level flow

1. Check out the exact Stable source tag.
2. Verify `JERKGRAM_RELEASE.json` and the published source manifest.
3. Configure your own Telegram API credentials and application identity.
4. Configure your own Apple signing environment.
5. Build using the build system included in the release source tree.

## Why the exact commands are not frozen yet

The final public build guide must describe the **actual first Stable materialized tree**, not a guessed development state. The command-level section is therefore completed only after the final Stable build path exists and has been verified.
