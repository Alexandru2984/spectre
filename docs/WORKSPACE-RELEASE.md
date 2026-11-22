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

Production activation and public verification are recorded below after the isolated release gate succeeds. The previous production shipment at review start was `2a0aff051f40-20261105T122347Z`. Restarting this ephemeral application clears existing live messages/events; there is no content backup or database migration. The deploy script preserves the old release and root-restricted configuration backup for rollback.

## Remaining product/operational work

Connect uptime/restart/429/5xx alerts to an operator-chosen destination. Observe field performance and voluntary user feedback before adding persistent accounts, uploads, push notifications or analytics. Search Console/indexing measurement needs operator-owned access; no external account was configured. A separate independent penetration/cryptographic assessment and host/Cloudflare account audit remain outside this bounded review. Anonymous identities, bearer invitations, copied content and physical memory/infrastructure retention retain the limitations described in the privacy page.
