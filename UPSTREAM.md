# Upstream

Jerkgram is based on **Telegram for iOS**.

```text
Repository   TelegramMessenger/Telegram-iOS
Tag          release-12.9.2
Commit       6ad963e5b62d354da79040f388ae2b9132fb17b8
```

## Relationship to upstream

Official Telegram for iOS is the implementation and comparison baseline for Jerkgram's current release line.

Jerkgram is an independent application. It must not present itself as the official Telegram client, and builders should use their own Telegram API credentials and application identity.

## Comparing Jerkgram with Telegram

Each Stable Jerkgram source tag records the exact upstream Telegram tag and commit used as its base. The intended comparison is therefore:

```text
Official Telegram release-12.9.2
            ↕
Jerkgram Stable source tag
            ↕
corresponding released Stable IPA
```

Release-specific hashes are published only once the final Stable artifact and public source snapshot both exist.

## Upstream notices

Applicable upstream copyright and license notices must remain preserved in the corresponding public source tree. Third-party components retain their own notices and license terms.
