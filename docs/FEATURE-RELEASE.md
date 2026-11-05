# Spectre 3 feature release

Date: 2026-11-05. This iteration implements the complete proposed feature package. Additional SEO work is deferred to the next iteration; existing metadata, sitemap and noindex protections are preserved.

## Delivered features

| Proposal | Delivered behavior |
| --- | --- |
| Replies | Direct threads, parent previews, thread detail, reply composer; at most 30 replies per parent. Shared monotonic/public deadlines and cascade removal prevent children outliving the parent. |
| Polls | 2–6 distinct choices, live totals/percentages, one mutable selection per random page token, bounded anonymous voter state. Anonymous tokens are not verified people. |
| Presence and aliases | Active page sessions, optional room-specific aliases, 20s heartbeats and 45s expiry; neither names nor counts verify identity. |
| Immediate updates | Serialized room revisions and capped asynchronous 20s long polling, immediate mutations/closure notifications, reconnect/backoff, visibility handling and snapshot fallback. Not an SSE/WebSocket implementation. |
| Moderation | Page-local hide/restore, reason-based reports expiring with the message, owner/global moderator review and removal, distinct creator burn capabilities. Reports alone never auto-delete a message. |
| Discovery | Built-in rooms plus explicitly listed public events with topic and activity. Private/unlisted events are excluded. |
| Event rooms | Topics, 15/30/60-minute durations, owner-only early closure; closure/expiry removes messages, polls, reports and sessions. Reserved random IDs fail closed after disappearance. |
| QR sharing | Participant invitation QR generated entirely in the browser using locked local qrcode-generator 2.0.4; no remote encoder receives links or keys. |
| Daily challenges | Seven rotating daily prompts, locally selected and translated; optional composer insertion without overwriting a draft. |
| RO/EN | Language selector, translated controls/dialogs/help/errors/dynamic counts and about/privacy content. Preference only is persisted. User message text, options, room names/topics and aliases are excluded from translation. |
| Private invitations | Separate 192-bit random reader and owner capabilities. Every scoped read/write/react/vote/report/presence/watch path checks access in the same coordinator as its mutation. Reader invitations do not confer moderation/closure rights. |
| Optional E2EE | Browser AES-256-GCM message/reply/poll text, 256-bit random content key, fresh 96-bit IV, 128-bit tag, authenticated room/kind/parent/option-count data. Only ciphertext and generic poll placeholders reach the server. Content keys travel in URL fragments, are removed from the address bar after loading, and never enter API URLs or persistent app storage. |

## Architecture and security

The Gleam HTTP boundary retains strict origin, content-type, UTF-8, framing, size, security-header and rate-limit checks. A single native OTP coordinator owns bounded state and serializes room authorization, snapshots, mutations and dependent cleanup. Separate message lifetime actors use absolute monotonic deadlines. OTP status/crash diagnostics redact state, requests, reasons and debug logs rather than dumping content/capabilities.

Bounds: 256 active managed events, five owned events per page token and ten per address; 500 messages globally and 100 per room; 30 direct children; 256 reaction/poll tokens and 64 reporter tokens per message; 1000 presence sessions globally and 100 per room; 100 watchers globally, 30 per room and four per address. Per-client and global HTTP budgets remain. These controls mitigate resource abuse; distributed attackers and shared NAT addresses remain limitations.

Operator moderation is configured in `/etc/spectre-link/environment`, created only when absent, root-owned 0600 in a 0700 directory. No secret was printed or committed. The unit reads it through EnvironmentFile; private room authorization is not bypassed by the global public-room moderator. The service retains its dedicated identity, immutable release, inaccessible home/checkout, resource caps and loopback-only networking. The 35s nginx upstream timeout supports the 20s event wait.

E2EE does not conceal room topics, aliases, timing, message type/parent links, presence, reactions, votes or traffic metadata. It does not protect against compromised browsers/origin code, copied invitations, screenshots or a participant redistributing plaintext. Shared-key rooms have no forward secrecy, key recovery, identity verification or individual member revocation. Close/recreate an event to replace its keys/participants. Tests below are not an independent cryptographic audit or an infrastructure compliance certification.

## Verification

- Nine Gleam/OTP unit tests passed, including independent cleanup inspected through the OTP system channel, full event-dependant cleanup without product reads, repeated parent/child deadline assertions and diagnostic redaction.
- 69 existing HTTP regressions and 42 new feature/authorization checks passed against the exact compiled release, then again for the isolated systemd preview before deployment. Includes private snapshot denial, cross-room references, poll changes, report permissions, creator/moderator controls, reserved-ID non-revival and watcher/address caps with explicit closure notification.
- Existing desktop/mobile browser suite passed: safe Unicode/HTML rendering, send/react/filter/search/sort/constellation/burn/share, keyboard, offline recovery, theme/motion/storage and 360/390/768/1440px layout.
- New multi-context browser suite passed: private invitations, fragment removal, ciphertext-only API bodies, encrypted replies/polls, live votes/presence/moderation, aliases, local hide, QR, RO/mobile, wrong content keys, missing invitations, fresh IVs, no content-key leakage to API requests, and event closure in another browser.
- Automated axe WCAG A/AA checks passed on the main flows, QR dialog, mobile Romanian private room, and EN/RO about/privacy pages. Automated accessibility checks do not replace a full manual audit.
- JavaScript syntax checks for all first-party scripts, Gleam format, ShellCheck, shipment export, and exact vendored-QR/package comparison passed. npm audit reported zero known advisories for the six-package development tree on this date.
- Public rollout verified global moderator report/removal using only a newly created unlisted temporary event, then closed it. Secret-file ownership/mode and runtime mount isolation were checked without printing credentials.
- Public idle long polling returned HTTP 200 after approximately 20.2s through Cloudflare and nginx, confirming that the proxy supports the hold duration.

GitHub-hosted CI is committed but has not run remotely because no push was performed. The same check script ran locally. Test mutations used isolated local releases or new temporary production events, never existing user conversations.

## Production activation

- Runtime code: `684315a9f87e` (the documentation commit does not alter runtime).
- Active release: `/opt/spectre-link/releases/684315a9f87e-20261105T024107Z`.
- Configuration backup: `/var/backups/spectre-link/684315a9f87e-20261105T024107Z`.
- Previous known-good release: `/opt/spectre-link/releases/66c3d9a0259c-20261105T023523Z`; the earlier 2.0 release is retained as well.
- Service active as `spectre-link`, zero automatic restarts, approximately 46 MiB memory at final inspection. Only loopback 4000 is used; unrelated 4001 is preserved; temporary 4400/4402 listeners are stopped.
- Final public flow passed: new encrypted event, invitation/QR, separate mobile participant, encrypted poll, live vote, Romanian controls and explicit owner closure. Final browser check produced zero console/CSP/page errors. Test events were closed, not archived.
- The first public check revealed expected-but-unnecessary 404 reads after closure. The final revision sends an explicit closed event so participants stop reading immediately; regression checks cover that behavior.

All implementation stages use the repository owner's existing author and committer identity, with no AI/co-author attribution. Additional SEO optimization remains the next stage.
