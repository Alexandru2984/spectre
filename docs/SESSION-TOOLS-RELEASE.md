# Spectre 3.2: live session tools

Date: 2026-11-22. Plan and acceptance: [SESSION-TOOLS-PLAN.md](SESSION-TOOLS-PLAN.md). The preceding 3.1 production evidence remains in [WORKSPACE-RELEASE.md](WORKSPACE-RELEASE.md).

## Delivered behavior

- One shared room spotlight, chosen by an authorized room moderator, with a participant preview and direct conversation access. Only a live main message from the same room can be selected. Expiry/removal/closure clears the pointer; highlighting never extends lifetime or creates a server content copy.
- Explicit resolve/reopen for main questions, using their creator capability or a room moderator. The unresolved filter follows this status. Replies remain readable without being treated as a certified answer.
- Close/reopen poll voting, using the creator capability or room moderation. Closed polls retain results and reject stale/concurrent vote changes with 409. Reopening preserves existing selections and the original expiry. Visual vote bars are independent from the lifetime progress bar.
- Read-only room presentation with large text, main-message/type/unresolved filters, chronological previous/next navigation, keyboard controls, direct spotlight selection, room timer and empty states. It starts from the spotlight when available and uses the current tab's authorized live/paused snapshot. No separate public URL, exported archive or persistent presentation state.
- EN/RO copy and both themes, mobile layouts and screen-reader focus/description support. Presentation and spotlight copies are removed when messages expire, are hidden locally, or removal/closure/navigation is processed. Asynchronous dialog close events cannot clear a newly reopened presentation.
- Corrected the offline-status race: a response finishing decoding after disconnection cannot hide the offline banner or claim a live connection. Terminal room locks also resist late error/status callbacks. Hosts restoring moderation rights bypass their old local participant cooldown, matching the server policy.
- Updated public information/privacy copy and local/CI/preview checks. No new runtime dependency, external service, Cloudflare setting, user account or persistent content storage.

## Security and access

Private read authorization remains mandatory on every scoped route, including when the caller knows a valid creator key. A different room's owner key cannot manage messages or spotlight. The global operator key moderates public rooms and does not take over unrelated private events. Status flags and spotlight IDs are metadata visible to the server, not authenticated identities or factual answer certification. The AES-GCM content/AAD protocol and separate access/encryption/owner keys remain unchanged.

The coordinator serializes votes, state changes, removal and expiry. There is at most one spotlight ID per room and every pointer references one of at most 500 live messages. Independent timers clear expired pointers without read traffic. No transition resets a message's deadline. Browser timers/update processing cannot erase screenshots, suspended-browser copies or physical memory; existing privacy limits remain applicable.

## Verification and activation

The full `scripts/check.sh` run passed against a compiled 3.2.0 shipment on isolated port 4400:

- 12 Gleam/OTP tests, including room/creator/operator authorization, unchanged expiry and spotlight cleanup without read traffic.
- 175 HTTP checks: 69 security/product, 42 feature/authorization, 22 owner-policy and 42 session-tool checks. This covers private-read requirements, wrong-room keys, invalid fields/kinds, live revisions, concurrent closed-poll votes, reopen/count preservation and expiry.
- All five browser suites: core desktop/mobile/axe, encrypted two-browser features, lifecycle regressions, workspace product flows and the new live session journeys.
- The new session suite verifies creator resolution/reopen, moderator-only spotlight, ciphertext-only poll transport, stale-client vote rejection, live reopening, uncorrupted vote bars, read-only keyboard presentation, Romanian, dark/light themes, mobile/desktop accessibility and secondary-copy cleanup on expiry/hide/burn/navigation/closure. Presentation dialogs have no horizontal overflow at 320/390/768px; the workspace suite retains 320–1440px checks.
- Deterministic delayed-decoding regressions preserve offline status after disconnection and terminal room closure after late responses. Existing draft, room, QR, moderation and private-key flows continue passing.
- Six-page static SEO/localization checks, JavaScript syntax, Gleam formatting, ShellCheck and the vendored QR comparison. npm audit reported no advisories; OSV reported no matches for the 13 locked Hex packages. Negative database lookups do not certify security.

Local ignored screenshots include `test-results/session-presentation-desktop.png` and `test-results/session-presentation-mobile.png`. A later read-only GitHub lookup confirmed [Release checks run 45039376332](https://github.com/Alexandru2984/spectre/actions/runs/45039376332) completed successfully for final runtime commit `383a25d93ad0f89774e07b1f8933c3634afa7989`. The release job and all steps, including full checks and screenshot upload, succeeded. No Git push was issued by this workflow; the remote/tracking branch was already synchronized when work resumed.

A follow-up landscape check found that a 568×320 viewport squeezed the presentation reading container to 24px. Patch 3.2.1 uses a single scrolling dialog at short heights, preserving the message area and reachable controls. The full session browser suite then passed with explicit 568×320 and 844×390 checks, in addition to portrait widths. The final patch is subject to the same complete isolated-shipment deployment gate below.

The final 3.2.1 shipment is active through the preview-gated deployment path:

- Runtime source: `383a25d93ad0` (subsequent documentation commits do not change runtime files).
- Active release: `/opt/spectre-link/releases/383a25d93ad0-20261122T134957Z`; its application metadata reports version 3.2.1.
- Restricted configuration backup: `/var/backups/spectre-link/383a25d93ad0-20261122T134957Z`.
- Immediate predecessor: `/opt/spectre-link/releases/e59ee1849aaf-20261122T134552Z`, version 3.2.0 with the landscape limitation noted above. The earlier 3.1 release `/opt/spectre-link/releases/cd35aa0bbf25-20261122T131459Z` is also retained. Follow OPERATIONS.md to choose and restore a suitable release/configuration pair.
- Observed production state: active as `spectre-link:spectre-link`, zero automatic restarts and about 47 MiB current memory. Only `127.0.0.1:4000` listens for this app; temporary 4400/4402 and former distribution 9100 have no listeners. nginx configuration validation passed.

Public curl checks through Cloudflare/nginx passed for all six EN/RO pages, with security headers and no observed analytics/challenge injection. The public dashboard.js, dashboard.css and i18n.js hashes match the committed files; a Romanian room query retains noindex.

The final public two-browser journey used a new private encrypted event. It verified fragment invitation handling and ciphertext-only poll transport, shared spotlight, creator resolution, poll freeze and server-side 409 rejection of a stale vote, read-only Romanian presentation, 568×320 landscape readability, mobile axe checks and event-closure cleanup. No JavaScript/CSP errors were observed. The test event was closed; existing user conversations were not inspected. Its screenshot is `test-results/production-session-mobile.png`.

An initial unpaced public journey hit the existing nginx `spectre_read_v2` burst limit (429) and timed out before the client retry interval; both message creations had succeeded, and that test event was closed during cleanup. The final journey used realistic action spacing and allowed the documented retry interval. Protection limits were not weakened. Shared-IP bursts can still delay updates, as described by the existing rate-limit/NAT boundary.

Restarts clear ephemeral state; no content backup/database migration was created. No other application unit was restarted and no Cloudflare/DNS/tunnel setting or external notification destination was changed.

## Remaining work

External alert delivery and Search Console need an operator-owned destination/account. An independent penetration/cryptographic assessment, host-wide audit, field performance measurements and actual search-indexing observations remain separate work. Anonymous tokens, bearer-link forwarding, shared-IP rate limits and participant-made copies retain their documented limits.
