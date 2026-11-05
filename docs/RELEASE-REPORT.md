# Spectre 2.0 release report

Date: 2026-11-05. Public site: https://spectre.micutu.com . Runtime code revision: `ef0ed808ae92`. The final documentation commit does not change the runtime.

## Delivered

- Public named rooms and room links, plus lobby/ideas/questions/after-hours navigation.
- Thought/idea/question categories; 15s/30s/1m/5m composer presets and server-enforced lifetime bounds.
- Three reactions with per-page toggling and bounded server state.
- Creator-only early burn using a cryptographic capability; hashes only on the server, raw key only in the creating page.
- Responsive live feed, search, category/mine filters, sorting, copy, countdowns, interactive constellation and message details.
- Theme/motion/view preferences, keyboard shortcuts, useful empty states, optional prompts, pause/resume and offline recovery.
- Server clock compensation; overlapping polling and stale room responses prevented.
- Local assets and strict CSP; public about/privacy pages, favicon/social image, metadata, robots and sitemap. Room/API responses receive noindex; user content never enters page/social metadata.
- Typed JSON and validated Unicode/size/control/room/TTL/reaction input; origin/framing checks, separate read/write budgets and bounded content/token storage.
- Independent server expiry, verified without relying on a registry read to clean up expired content.
- Distribution/port scanning removed; service runs from an immutable compiled release as a dedicated identity.
- Scoped nginx/systemd templates, preview-before-switch deployment, restricted configuration backups and rollback tooling.
- Locked development checks, pinned GitHub Actions with read-only permissions, dependency update configuration, security policy and operational documentation.

## Verification evidence

- Seven Gleam unit tests passed, including Unicode/escaping, malformed JSON/types, control/TTL bounds, independent registry cleanup via OTP state inspection, separate budgets, room isolation, reaction toggle/change and creator burn authorization.
- 69 HTTP checks passed against the compiled shipment and again under the dedicated preview systemd identity. These cover public assets/SEO/noindex, framing, limits, origin rejection, room isolation, burn keys, reactions, expiry and write-budget exhaustion without blocking reads.
- Browser workflows passed with Chromium via Playwright 1.64.1; automated axe 4.14.0 WCAG A/AA checks passed on desktop, the information dialog, mobile dark/light, about and privacy pages. Layout checked at 360, 390, 768 and 1440px. Hostile HTML is displayed as text; no message content/burn keys are written to browser storage.
- JavaScript syntax, Gleam format, ShellCheck, shipment export and workflow YAML/pinned-action validation passed.
- npm audit: zero known advisories. OSV: zero matching advisories across 13 locked Hex packages on this date. Negative scans have coverage limits.
- Public HTTPS HEAD checks returned 200 for homepage, about/privacy, robots, sitemap, CSS, JS, social image and health. One strict CSP header, nosniff and correct room noindex were confirmed.
- A normal public browser flow in a fresh temporary room passed: connect → post → react → creator burn. No hostile test payloads or tests against other users' messages were used in production. The created message was burned immediately.
- Initial public checks exposed Cloudflare beacon/JavaScript-detection injection blocked by CSP. `no-transform` stopped the observed injections; final public mobile browser check reported **zero errors**. No global Cloudflare security setting or CSP relaxation was used. Existing upstream bot policy rejected Python urllib's default client while normal curl/browser checks succeeded; edge behavior is distinct from app routing.

## Production state

- Active release: `/opt/spectre-link/releases/ef0ed808ae92-20261105T013442Z`.
- Previous known-good compiled release: `/opt/spectre-link/releases/108f36d87459-20261105T013250Z`.
- Active symlink: `/opt/spectre-link/current`.
- Latest configuration backup: `/var/backups/spectre-link/ef0ed808ae92-20261105T013442Z` (restricted directory).
- Unit: `spectre-link-canary.service`, active as `spectre-link:spectre-link`, zero automatic restarts after activation, approximately 45 MiB memory at final inspection.
- HTTP listens only on `127.0.0.1:4000`; the former distribution listener on 9100 is absent. The unrelated listener on 4001 was preserved. Temporary test listeners on 4400/4402 are stopped.
- Checked from inside the service mount namespace: developer home and `/srv` are inaccessible; the root-owned entrypoint is readable and not writable by the service account.
- `ProtectSystem=strict`, `ProtectHome=yes`, `NoNewPrivileges=yes`, core limit zero and loopback-only systemd IP policy verified. Crash dump output is `/dev/null`; public outbound network access is denied for the service.
- nginx configuration validation passed before graceful reload. Only this application's vhost/zones/snippets and systemd unit changed; no other app restart or DNS/tunnel reconfiguration was performed.
- Rebar3 3.26.0 was extracted from the configured distro package and installed to the user's local bin for repeatable builds, without upgrading the host's Erlang or other application packages. Runtime does not need it.

The second deployment exercised the upgrade path with an existing compiled release and retained it for rollback. The failed-activation rollback branch was reviewed, not deliberately triggered against the live service. Initial-adoption limitations and manual rollback are documented in OPERATIONS.md. Deployment cleared prior ephemeral messages as expected; no message archive was created.

## Remaining boundaries and priorities

This is a functional public ephemeral board, not a private messenger or a vulnerability-free certification. All rooms are public; there is no E2EE, identity verification, secure physical erasure or distributed replication. Anonymous reaction tokens do not prevent deliberate vote manipulation. Screenshots/copies, edge policies/logs, NAT-shared budgets and distributed abuse remain relevant limits.

Next priorities: moderation/reporting before wider promotion; operator-owned external alerts; independent penetration testing; authenticated private rooms and separately reviewed client-side encryption. The audit has an incident runbook and a solo walkthrough; no independent/operator-led incident tabletop or compliance certification was performed.

CI is committed and the equivalent checks ran locally. GitHub-hosted Actions have not run because no push was made. All change commits use the pre-existing owner identity for author and committer, with no co-author/AI attribution. Existing dependency updates were preserved and integrated.
