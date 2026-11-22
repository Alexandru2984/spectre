# Spectre 3.1 workspace release

Date: 2026-11-22. Review and acceptance plan: [PRODUCT-4-PLAN.md](PRODUCT-4-PLAN.md). Security findings and limitations: [SECURITY-AUDIT.md](SECURITY-AUDIT.md#reassessment-2026-11-22).

## Delivered

- Responsive room workspace with readable typography, a compact brand header, desktop composer/conversation columns, mobile room navigation and a contextual compose shortcut. Both themes, English/Romanian and reduced motion remain available. No new runtime npm dependency or remote asset provider.
- Complete chronological conversation dialogs, unanswered questions, reply-count sorting, search through poll choices/aliases and conversation focus.
- Conversation, brainstorm, Q&A and team check-in templates. Live owner name/topic, questions-only/pause and 0/5/15/30s per-page posting policies. Private read and owner capabilities remain separate.
- Up to 12 isolated room drafts in page memory, including poll choices/lifetime/reply context; recent-room navigation preserves in-memory invitation controls. Reloading loses drafts. Managed-event closure/expiry clears its draft and controls. Host policies, not anonymous identity verification, govern posting.
- Fixed report preview retention, obsolete async dialog/snapshot responses, paused burn cascades, initial reconnect failure, Unicode character counts, typed-during-send draft preservation and closed-room form cleanup. The check log now uses a private temporary file.
- Public about/privacy copy and current security policy match the implementation. Six static EN/RO pages retain self-canonical, reciprocal language alternates, public-only structured data/sitemap and noindex room/API responses. Social image/favicon match the redesign; no ranking or indexing result is claimed.
- Full local/CI suite includes current npm/Hex advisory lookups and product/lifecycle regressions. Deployment now tests all four browser suites and HTTP policies against the exact isolated systemd shipment before activation.

## Verification completed before activation

`PLAYWRIGHT_BROWSERS_PATH=/home/micu/.cache/ms-playwright ./scripts/check.sh` passed against a compiled 3.1.0 shipment on isolated port 4400:

- 10 Gleam/OTP tests, including owner authorization, bounded cooldown state, independent expiry and diagnostic redaction.
- 69 HTTP security/product checks, 42 feature/authorization checks and 22 owner-policy HTTP checks, including live revision and real cooldown expiry.
- Six-page static SEO verification and deterministic Romanian generation; JavaScript syntax, Gleam formatting, ShellCheck and vendored QR comparison.
- Existing desktop/mobile browser and axe WCAG A/AA journeys; private/encrypted two-browser replies, polls, moderation and closure.
- Lifecycle regressions for initial reconnect, burn cascade while paused, report expiry, delayed reports across navigation and suspended decoding after event closure.
- Product journeys for templates/privacy preservation, isolated drafts, 500-emoji character counting, recent private rooms, live host policies/cooldowns, unanswered questions, full threads and focus. No horizontal overflow at 320/360/390/768/1440px; axe also checks settings, thread dialogs and Romanian mobile.
- npm audit: no advisories reported for the locked development tree. OSV querybatch: no matching advisories for 13 locked Hex packages. These are dated database results with coverage limits.

Screenshots are local ignored artifacts under `test-results/`, including `product-desktop.png`, `product-desktop-focus.png`, `product-mobile.png` and both theme/mobile smoke captures. GitHub-hosted CI has not been executed remotely; no Git push is part of this release.

## Activation

The isolated systemd shipment passed all 10 unit tests, 133 HTTP checks, SEO checks and all four browser suites before activation. nginx configuration validation passed before its graceful reload. The production switch completed successfully:

- Runtime source commit: `cd35aa0bbf25` (subsequent documentation commits do not change the runtime).
- Active release: `/opt/spectre-link/releases/cd35aa0bbf25-20261122T131459Z`.
- Root-restricted configuration backup: `/var/backups/spectre-link/cd35aa0bbf25-20261122T131459Z`.
- Previous release/rollback target: `/opt/spectre-link/releases/2a0aff051f40-20261105T122347Z`.
- Observed service: active/running under `spectre-link:spectre-link`, zero automatic restarts, approximately 47 MiB current memory just after activation. HTTP remains `127.0.0.1:4000`; temporary 4400/4402 and former distribution 9100 have no listeners.

Public verification through Cloudflare/nginx passed for all six static EN/RO pages: 200 responses, correct language, security headers and no observed automatic analytics/challenge script injection. Public JS/CSS/i18n/favicon/social-image hashes match the committed files. A Romanian room query retains noindex. Actual public gzip payloads measured 22,652 bytes for dashboard.js (69,372 source bytes) and 9,281 for dashboard.css (35,004 source bytes); this is a transfer-size observation, not a field Core Web Vitals score.

A separate public two-browser verification created one private encrypted event using a fresh unlisted starting room. It verified fragment invitation handling, ciphertext-only posting, peer delivery, encrypted reply, the full thread, live host pause, Romanian mobile layout/axe, owner closure and immediate peer lock/content removal. No JavaScript/CSP errors were observed. The synthetic event was closed; existing user conversation content was not inspected. Its mobile screenshot is `test-results/production-workspace-mobile.png`.

A raw Python urllib request received a Cloudflare 403, while curl and the normal Chromium journeys above succeeded. No Cloudflare account settings were changed to weaken that behavior; generic automated-client/edge-policy coverage is not claimed.

Restarting the ephemeral application cleared the previous live state as documented; no content backup or database migration was created. The previous release remains available for rollback using OPERATIONS.md. No Git push, other application restart, new credential export, analytics integration or DNS/tunnel configuration change was performed.

## Remaining product/operational work

Connect uptime/restart/429/5xx alerts to an operator-chosen destination. Observe field performance and voluntary user feedback before adding persistent accounts, uploads, push notifications or analytics. Search Console/indexing measurement needs operator-owned access; no external account was configured. A separate independent penetration/cryptographic assessment and host/Cloudflare account audit remain outside this bounded review. Anonymous identities, bearer invitations, copied content and physical memory/infrastructure retention retain the limitations described in the privacy page.
