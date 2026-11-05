# Spectre-Link: product and hardening plan

Date: 2026-11-05. Scope: this application, its systemd service, and its nginx vhost. Other VPS applications and global Cloudflare settings are outside the change set.

## Baseline

Gleam 1.16 / Erlang OTP 27, Mist 6.0.3, no database, one local registry. The repository initially had no tests, CI, static asset files, or release tooling. Two dependency files already contained an uncommitted update; preserve that update and integrate it when replacing the legacy JSON parser.

Production is behind a Cloudflare route and nginx. The application listens on loopback. Erlang distribution and EPMD also listen on loopback; public exposure of those ports was **not** observed. A second, unrelated listener uses port 4001: do not probe or restart it.

## Delivery sequence

1. **Audit and plan**: record evidence, threat model, priorities, scope, incident response and honest retention/privacy limits.
2. **Security foundation**: use a real JSON decoder/encoder; validate content, byte length, TTL, framing and origin; bound writes and reads; eliminate retained expired records; generate random identifiers; set headers in the application; use a fixed configured loopback port; disable unnecessary distribution.
3. **Product API**: isolate public rooms, add message categories, reactions, creator-only burn capabilities and aggregate room statistics. Validate everything on the server; room names are not access control. Do not persist message bodies in browser storage.
4. **Product experience**: responsive accessible interface, room creation/sharing, live feed, constellation view, search, filters, sorting, TTL presets, countdowns, copy, reactions, burn controls, useful empty/error/offline states, keyboard shortcuts, reduced motion and light/dark themes. Keep dependencies small and assets local.
5. **Verification**: unit and HTTP regression tests for validation, expiry, capability checks, rate limits and room isolation; browser checks on desktop/mobile, keyboard operation and hostile content rendering. Use an isolated local server; do not inject audit payloads into the public room.
6. **SEO and CI (last)**: public metadata, local favicon/social image, robots/sitemap, index only useful public pages, reproducible automated checks, documented operation and release/rollback procedure.
7. **Production hardening and release**: dedicated service account, immutable built release, no developer-home access, no compilation at startup, scoped nginx configuration and independent read/write limits. Validate configuration before a scoped reload, then check public routes and service identity. Restarting discards live ephemeral messages; no migration or backup of message content.

Each completed stage receives a separate commit using the repository owner's existing author identity, with no AI attribution or co-author trailer. Changes to other applications, analytics integrations, account systems, billing and persistent storage are not implied by this plan.

## Follow-on features

- Invite-only rooms with a reviewed authentication and authorization model.
- Opt-in client-side encryption with a separate threat model (keys never sent to the server).
- Real-time streaming after designing subscriber limits and reconnect behavior.
- Moderation/reporting and abuse triage before promoting the public service at scale.
- Explicitly opt-in browser notifications, room QR sharing, multilingual interface.
- Real distributed message replication only with authenticated private networking, TLS distribution, failure semantics and cluster tests. Connecting BEAM nodes alone does not replicate the current registry.

These are proposals, not claims of shipped functionality. Avoid adding accounts, uploads, remote embeds or external vendors before their privacy and abuse implications are designed.

## Release acceptance

- Invalid JSON, oversized/empty content, invalid TTL and forbidden origins fail safely.
- Expiry works without traffic and expired text is removed from application-owned records.
- One room cannot retrieve or mutate another room's messages.
- A message can only be burned with its returned, unguessable capability.
- No XSS from message text, no content in browser storage, no indexing/caching of messages.
- Read polling fits within read limits; sending uses a separate budget.
- Usable at 360px and desktop widths, with keyboard and reduced motion.
- Service binds only to its configured loopback port and runs with no developer-home access.
- Checks pass, releases are reproducible, and rollback is documented.
