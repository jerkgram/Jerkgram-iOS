# Source Transparency

Jerkgram's public-source policy is release-oriented.

## The contract

For every Stable release, the project should be able to answer one question without ambiguity:

> **Which exact source snapshot corresponds to this exact released IPA?**

The release record binds together:

- Jerkgram version;
- public Git tag;
- exact Telegram upstream tag and commit;
- Stable IPA SHA-256;
- public source archive SHA-256;
- deterministic source manifest.

## Release-source flow

```text
Official Telegram for iOS
          ↓
Jerkgram development pipeline
          ↓
final materialized Jerkgram source
          ├──→ Stable IPA
          └──→ verified public source snapshot
```

The public snapshot is exported from the final materialized release tree. It is not a separately maintained showcase fork.

## Export invariants

A release-source exporter should follow these rules:

1. **Release tree only.** Export runs only after the canonical release tree is fully materialized.
2. **Production bytes stay unchanged.** Export does not cosmetically rewrite runtime/build source.
3. **Explicit exclusions only.** Non-production exclusions are narrow, reviewed and deterministic.
4. **Fail closed on sensitive data.** Signing material, secrets or ambiguous unsafe files stop the export rather than being silently redacted.
5. **Manifest everything published.** The final snapshot gets deterministic per-file hashes.
6. **Verify correspondence.** Non-excluded production files must match the materialized release tree byte-for-byte.

## Internal development history

The public source repository does not need to contain every historical development transformation used to arrive at the final source tree. Development-only orchestration, temporary diagnostics and internal release-engineering records remain separate when they are not part of the corresponding production/build source.

The important invariant is not the visibility of every historical step. It is that the public snapshot contains the **real source corresponding to the released application**.

## Signing and secrets

Never publish:

- personal signing certificates or private keys;
- provisioning profiles containing private signing identity data;
- session credentials or auth material;
- tokens or private secrets;
- private developer identities that are not required as public source constants.

The exporter should fail if such material is found in export scope.

## Stable release record

Release metadata is stored in `JERKGRAM_RELEASE.json` and completed only after the final Stable IPA and source snapshot exist.
