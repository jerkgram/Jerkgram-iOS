# Security Policy

Security issues should be handled with care, especially when a report may contain user data, credentials, tokens or a working exploit.

## Sensitive reports

Do **not** post secrets, private user data, live credentials or a complete working exploit in a public GitHub issue.

If GitHub private vulnerability reporting is enabled for this repository, prefer the repository's **Security → Report a vulnerability** flow.

If no private reporting channel is available yet, contact the Jerkgram community without posting sensitive details and request a private contact path.

## Useful report content

When safe to share, include:

- Jerkgram version/build;
- iOS version and device model;
- affected feature;
- minimal reproduction steps;
- expected vs. actual behavior;
- whether user data, credentials or release integrity may be affected.

## Release integrity

The public-source release process is designed to reject export scope containing signing material or secrets rather than silently publishing or rewriting them.
