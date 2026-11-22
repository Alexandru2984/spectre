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

Local ignored screenshots include `test-results/session-presentation-desktop.png` and `test-results/session-presentation-mobile.png`. Remote GitHub CI has not been run or claimed; no push is part of this iteration.

Production activation is recorded after the isolated systemd preview gate succeeds. The active predecessor at the start of this iteration was `/opt/spectre-link/releases/cd35aa0bbf25-20261122T131459Z`. Restarts clear all ephemeral state; the deployment path retains the previous release and restricted configuration backup for rollback.

## Remaining work

External alert delivery and Search Console need an operator-owned destination/account. An independent penetration/cryptographic assessment, host-wide audit, field performance measurements and actual search-indexing observations remain separate work. Anonymous tokens, bearer-link forwarding and participant-made copies retain their documented limits. Remote GitHub CI is not claimed without a push.
