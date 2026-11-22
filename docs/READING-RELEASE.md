# Spectre 3.4: reading and browser lifecycle

Date: 2026-11-22. Baseline: 3.3.0. Scope: READING-PLAN.md.

## Behavior

- Reading view hides the composer and gives the conversation a centered, wider column. Writing, reply, N and the mobile shortcut restore the composer without clearing text, poll options, type, lifetime or reply context.
- The mobile shortcut appears when neither the composer nor the reading-view writing control is visible. It does not cover the restore controls just because the composer is hidden.
- A hidden-message notice remains available while other messages are visible. Undo restores the most recent hide; show-hidden restores only the current room's still-live choices. Hiding a parent still hides its replies. Restoration cannot extend lifetime or revive expired messages. Keyboard focus moves to a usable control after hide/restore.
- Constellation excerpts, hit objects and pixels clear when inactive, empty, expired, navigated away from or locked. Message/share/moderator/settings/report/delete/presentation dialog cleanup is synchronous on app dismissal and Escape, with protection against queued native close events erasing a reopened dialog.
- Late report, creator-delete and settings responses cannot dismiss or write errors into a newer dialog. Successful current-room server changes remain reflected in the authorized snapshot.
- A late event-closure response cannot lock a different room or clear that room's draft. Repeated close submissions are disabled until the request finishes; actual event closure still reaches its participants.
- New controls and public information are available in EN/RO and both themes. No package, skill, persistent content store or external vendor is added.

## Targeted verification

The new browser reading/lifecycle journey reproduced the retained constellation excerpts before the fix. It now covers inactive pixels/excerpts, empty-room navigation, TTL expiry, immediate dialog clearing, native close/reopen races, held real mutation responses, draft fields, writing entry points, room-scoped undo/restore and expired hidden entries. It also checks no conversation/key/hide data enters browser storage.

Reading controls were checked at 1440×1000, 320×844, 390×844, 768×844 and 568×320 with EN/RO, both themes, no horizontal overflow and no automated axe WCAG A/AA violations. Visual captures in ignored `test-results/reading-1440.png` and `reading-390.png` use local synthetic content. Existing lifecycle/session journeys passed after cleanup changes. The compiled-shipment and activation evidence follows below; local results alone do not imply remote CI.

## Compiled shipment and activation

The exact 3.4.0 shipment passed the isolated systemd preview gate: 12 unit tests, 175 HTTP checks, all six browser suites, six-page SEO/localization checks, JavaScript syntax and Gleam formatting. npm audit reported zero advisories and OSV returned no matches for the 13 locked Hex packages at verification time. ShellCheck, deterministic locale generation and the vendored QR comparison also passed before the release commit.

- Runtime source: `83fcdb5d979f`.
- Active shipment: `/opt/spectre-link/releases/83fcdb5d979f-20261122T184522Z`.
- Restricted configuration backup: `/var/backups/spectre-link/83fcdb5d979f-20261122T184522Z`.
- Previous release/rollback target: `/opt/spectre-link/releases/46fcdfed473a-20261122T181607Z`, version 3.3.0. Use OPERATIONS.md for rollback; restart clears ephemeral state.

nginx validation and public health passed. The service is active as `spectre-link:spectre-link`, with zero automatic restarts; the compiled application metadata confirms 3.4.0. The application listener is loopback 4000 and temporary 4400/4402 listeners have been released.

Public static checks through Cloudflare/nginx passed for all six EN/RO pages, strict existing security headers, a Romanian room query's noindex header and exact hashes for dashboard.js, dashboard.css, i18n.js, icons.svg and social.png.

The paced public browser journey passed in an owned private encrypted event: ciphertext-only submission, an independently decrypted second participant view, draft-preserving reading/N, hide/undo/restore, native share close/reopen, inactive canvas cleanup, desktop and Romanian/light mobile axe checks, no horizontal overflow and no observed JavaScript/CSP errors. Closure reached the second participant, cleared canvas/excerpts and rejected the closed invitation with 404, matching the existing HTTP contract. Both public test events were closed; no existing public conversations were inspected. Final public captures, visually reviewed, are `test-results/production-reading-desktop.png` and `test-results/production-reading-mobile.png`.

CI and deployment scripts now both run the six browser journeys. No push or new remote-CI result is claimed; local and compiled-preview checks are the evidence for this revision. Commits retain the owner's existing author/committer identity without co-author trailers. No skill/package installation or broader infrastructure change was required.
