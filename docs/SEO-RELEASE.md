# Spectre SEO follow-on release

Date: 2026-11-05. The complete feature package was delivered first (FEATURE-RELEASE.md). This separate follow-on implements SEO-PLAN.md.

## Delivered

- Six complete public HTML pages: `/`, `/about`, `/privacy`, `/ro`, `/ro/about`, `/ro/privacy`. Romanian copy is available without JavaScript.
- Accurate feature-oriented titles, descriptions, locale-specific Open Graph/Twitter metadata and image alt text. Public homepage content explains ephemeral conversations, polls, private invitations and encryption limits, with relevant internal links.
- Self-canonical URLs and reciprocal fully qualified EN/RO/x-default alternates on all six pages. Sitemap contains exactly those six pages, with no room, message, participant or invitation links.
- Honest WebSite/WebPage JSON-LD data, with matching language/URL and no fabricated ratings, reviews or user counts. JSON-LD is non-executable data; the strict script CSP is unchanged.
- Explicit public URL determines initial language. Switching EN/RO updates the public route, canonical/social fields and internal links in place, preserving in-memory private-room access/encryption keys and drafts. User text remains excluded from translation.
- Deterministically generated `.ro.html` variants checked in and verified against the shared catalog/templates in CI. Generate with `node scripts/build-locales.mjs`; verify with `--check`.
- Scoped origin gzip for HTML/static CSS/JS/SVG/XML, with message JSON excluded from configured gzip types. No CSP relaxation or Cloudflare global setting change. No-transform and message API no-store remain.

## Verification

The complete check script passed: nine Gleam/OTP unit tests, 69 original HTTP regressions, 42 feature/authorization checks, the new six-page SEO checks, existing browser/axe flows and the private/encryption multi-context suite. This includes EN/RO information pages, mobile layout, wrong/missing keys, live closure and switching language while encrypted access remains usable. npm audit reported zero known advisories for the locked development dependencies.

The exact compiled release then passed SEO and HTTP/feature checks under the isolated preview service before the scoped production switch. nginx validation passed before reload. Final public curl checks verified 200 responses, rendered language, self-canonical, reciprocal alternates, structured data and absence of automatic beacon/challenge injection on all six pages. A Romanian room query retained noindex.

A public /ro flow in a new temporary encrypted event passed: create event, invitation/QR, independent mobile participant, EN/RO round trip without key loss, encrypted message delivery and owner closure. No console/CSP/page errors were observed. The event was closed; no existing user messages were inspected.

Measured public dashboard JavaScript transfer: 56,009 source bytes vs 18,637 gzip bytes (approximately 66.7% smaller). This is an asset-size measurement, not a field Core Web Vitals or ranking claim.

## Production state

- Runtime source: `2a0aff051f40` (documentation commits do not alter runtime).
- Active release: `/opt/spectre-link/releases/2a0aff051f40-20261105T122347Z`.
- Configuration backup: `/var/backups/spectre-link/2a0aff051f40-20261105T122347Z`.
- Previous release: `/opt/spectre-link/releases/684315a9f87e-20261105T024107Z`.
- Service active as the dedicated `spectre-link` identity, approximately 45 MiB RAM, zero automatic restarts after activation. Port 4000 remains loopback-only; unrelated 4001 is preserved; temporary 4400/4402 and former distribution 9100 are absent.
- Existing root-owned moderation environment is preserved. No credentials, content archive, external tracking vendor, DNS/tunnel change or other app restart was introduced.

## Boundaries and next measurement

Search Console ownership, sitemap submission, actual Google indexing/ranking and field Core Web Vitals have not been verified. Public browser/curl behavior and local technical checks do not substitute for those external observations; existing edge bot policies can treat other clients differently. Structured data is not a promise of a rich result. Future work should use real search/crawl/performance evidence and useful content rather than indexing ephemeral conversations.

GitHub-hosted CI has not run remotely because no push was made. Local equivalent checks passed. Commits retain the existing owner's author/committer identity without AI/co-author attribution. Private invitation/E2EE limits remain those documented in FEATURE-RELEASE.md and the public privacy page; no independent crypto audit is claimed.
