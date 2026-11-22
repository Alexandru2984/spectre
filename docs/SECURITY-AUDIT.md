# Security audit and threat model

The opening assessment below preserves the original 2.0 review. Spectre 3 adds managed/private rooms and optional browser encryption; see FEATURE-PLAN.md for those trust boundaries. The 2026-11-22 reassessment at the end and PRODUCT-4-PLAN.md cover the current workspace release.

Date: 2026-11-05. Assessment: source review, dependency-source inspection, bounded local checks, read-only examination of the application's service/vhost, and public response headers. This is not an independent penetration test or a host-wide compromise investigation. No user message bodies were read for the audit.

## Findings at baseline

| ID | Severity | Evidence / impact | Planned remediation |
| --- | --- | --- | --- |
| S01 | High | `parse_message_json/1` uses regex rather than JSON parsing and returns character lists where Gleam expects UTF-8 binaries. Unicode, escaping, malformed documents and runtime behavior are unreliable. | Typed `gleam_json` decoding and encoding; strict schema validation. |
| S02 | High | `node_registry` stores complete message content in its dictionary and removes expired entries only on `ListMessages`. Actors exiting do not erase the registry copy. | Independent expiration and periodic cleanup, deadline checks on reads/writes. |
| S03 | High | Public service runs as the developer user, with access to the home directory and a writable checkout/cache. Erlang distribution starts automatically under that identity. A code execution bug could expose unrelated credentials. | Dedicated system identity, read-only release, inaccessible home, distribution disabled by default. |
| S04 | Medium | `location = /api/messages` applies the 10/minute POST zone to GET too; dashboard polls twice/2s. Normal use hits 429s and errors are swallowed. | Separate write budget from read budget; explicit client error/backoff. |
| S05 | Medium | Application responses have no CSP/security headers; they depend on one proxy route. | Application-level security headers and matching nginx policy. |
| S06 | Medium | No origin/content-type checks, no application-level abuse budget, weak timestamp/random IDs. | Same-origin write policy, JSON-only requests, bounded per-client/global budgets, cryptographic IDs. |
| S07 | Medium | Body-size handling relies on Content-Length and Mist 6.0.3 `read_body`; unsupported framing is not explicitly rejected. | Require bounded Content-Length for mutations, reject transfer encoding, verify actual bytes. nginx buffers public requests. |
| S08 | Medium | No tests/CI or repeatable deployment; startup invokes `gleam run`, and launch scripts target a different directory. | Tests, built releases, portable scripts, checked-in scoped configuration. |
| S09 | Low | IDs/internal BEAM node names and operational architecture exposed through public API. | Public node aliases and minimal aggregate status. |
| S10 | Product/privacy | README claims “no trace” and distributed messaging; neither physical erasure nor replication is implemented. Browser screenshots, swap, crash dumps and proxy logs remain possible. | Accurate public privacy model; no false E2EE or replication claims. |

EPMD (4369), distribution (9100), and HTTP (4000) were bound to 127.0.0.1 at inspection, not publicly exposed. Existing global SSH/firewall/TLS settings are not changed on behalf of this project.

## STRIDE and blast radius

Top risks: denial of service through anonymous write/resource abuse (high likelihood, medium impact); information disclosure through retained content or public-room misunderstandings (medium likelihood, high impact); privilege escalation/lateral movement from a compromised application sharing the developer identity (medium likelihood, high impact).

All rooms in this release are public. Anyone knowing a room name can read it. This service is unsuitable for secrets. No user count, revenue or incident cost data is available; financial loss/ALE and number of affected users cannot responsibly be quantified. Worst case before isolation: application memory, the developer user's accessible files/credentials, and potentially other applications accessible through those credentials. After isolation, the intended boundary is this service's active in-memory content and runtime.

Trust boundaries: browser → Cloudflare → nginx → loopback Mist → registry/actors. Client headers are untrusted except where nginx overwrites them. No external analytics library or new data processor is added. Existing Cloudflare traffic processing and nginx/journal retention remain operator concerns; no DPA/compliance status is inferred.

Erlang documentation cautions that distribution cookies do not provide a cryptographically secure transport; any future multi-host deployment must use authenticated TLS and explicit network restrictions: https://www.erlang.org/docs/29/system/distributed.html and https://www.erlang.org/doc/apps/ssl/ssl_distribution.html .

## Detection and response

Current external alerting/on-call ownership and MTTD are unknown. No claim of automated incident alerting is made. Suggested operator alerts: public health endpoint failing for 2 minutes; service restart count increasing; sustained 429/5xx bursts; memory pressure approaching the service limit. Monitor counts/status only, not bodies or burn keys. Initial target MTTD: 5 minutes once an operator connects these checks to an alert destination.

Incident runbook:

1. Confirm service health and recent restart/error counts without exporting user content. Check only this vhost/service initially.
2. For suspected application compromise, stop `spectre-link-canary`, keep the rest of the VPS running, and preserve restricted infrastructure logs/configuration as appropriate. Stopping drops all messages.
3. Revoke any credentials the service could access, including the developer account's credentials if the old shared-user service was compromised. Do not copy secrets into issues or commit messages.
4. Build a reviewed release from a known commit, apply the root-owned service template, validate nginx, and restore only this application.
5. Check public health, normal read/write behavior in a dedicated temporary room, service identity and loopback binding. Investigate lateral access before declaring containment.
6. Record impact, timeline, affected data and notification decisions with the operator. Applicable legal duties require a separate assessment; none is certified by this audit.

Tabletop: not independently exercised with the operator; local smoke/regression checks are not an incident-response tabletop. A deployment/rollback rehearsal will be documented when completed.

## Verdict

Baseline: **mitigate before promotion**. Anonymous public content, upstream edge behavior, physical memory erasure and absence of external alerting remain explicit residual risks even after code fixes. Track final verification and limitations in the release report rather than claiming the site is vulnerability-free.

## Remediation and local verification

The original ten findings are addressed in code and checked-in operational configuration. Runtime isolation and nginx activation must additionally be confirmed in the release report after deployment.

- S01: typed JSON decoding, standard escaping, UTF-8/string/byte/control/TTL/type validation. Unicode round trips and malformed data are covered by unit/HTTP checks.
- S02: registry expiry messages, periodic sweeps and monotonic read/write deadlines. A regression test inspects OTP state **before any registry API call** after expiry and confirms that retained entries are gone.
- S03: distribution and automatic port scanning removed. A dedicated service identity, inaccessible home/checkout, root-owned release, disabled core/crash dumps, resource limits and loopback-only network policy are defined in the new unit.
- S04: separate method-dependent nginx keys and independent application read/write budgets; UI polling every four seconds with non-overlapping requests, Retry-After/backoff and visible network state.
- S05: application and proxy CSP/security headers. No external script, inline script/style, user HTML rendering or remote embed. SVG assets are local fixed assets.
- S06: exact-origin/Fetch Metadata checks for browser writes, JSON-only mutation bodies, bounded per-client/global windows and cryptographic 192-bit identifiers/capabilities. Creator keys are hashed at rest in memory and omitted from lists. Anonymous reactions remain intentionally susceptible to a determined client minting fresh tokens, subject to write/capacity limits.
- S07: unsupported transfer encoding and missing/oversized lengths rejected; actual byte length checked; errors close the upstream connection. Public traffic remains behind nginx request buffering/timeouts.
- S08: unit tests, HTTP regressions, browser/axe checks, reproducible shipment checks, pinned read-only CI workflow and a preview-before-switch deployment script. Port availability guards prevent test mutations against a pre-existing listener.
- S09: only the public alias `local` is returned. Health/stats expose minimal non-sensitive status/counts.
- S10: README, in-app guide and public privacy page explain public rooms, no E2EE, loss of burn controls on reload and limits of expiry/physical erasure. No distributed replication is claimed.

Additional product boundaries verified: room isolation for read/react/burn; wrong or missing burn capability rejected; reaction changes/toggles have bounded token storage; room names reject traversal, uppercase and trailing newline; room URLs and API responses are noindex; message bodies and keys are not written to browser storage. The frontend provides text-only rendering, so hostile HTML is displayed literally.

Dependency review on 2026-11-05: npm audit reported zero known advisories for the locked development tree; OSV querybatch returned zero matching advisories across 13 locked Hex packages. Mist's upstream security page listed no published advisories: https://github.com/rawhat/mist/security . These are dated negative lookups with database coverage limitations, not proof of absence. No host-wide package update or OS vulnerability certification was performed.

Pre-release check suite: seven Gleam unit tests, 69 HTTP checks against an isolated compiled shipment, browser workflows at desktop/mobile sizes, automated axe WCAG A/AA checks including static information pages, JavaScript syntax, Gleam formatting and ShellCheck. GitHub-hosted CI is configured but has not been run remotely without a push.

Solo runbook walkthrough: considered failed preview startup, failed proxy validation, capability leakage and suspected app compromise. The preview gate leaves production unchanged until it succeeds; configuration validation occurs before reload; failed activation restores saved configuration/previous release where available. A leaked burn key can destroy only its message in its room, not grant server access. Suspected compromise requires stopping this service, preserving restricted infrastructure evidence, and investigating credentials reachable by the prior shared identity. No real incident or operator-led tabletop was staged. Automatic external alerting/on-call ownership remains unconfigured.

### Edge integration check

The first public browser smoke succeeded for posting/reaction/burn, but exposed pre-existing Cloudflare automatic beacon and JavaScript-detection injection blocked by the strict CSP. Public assets now request `Cache-Control: public, no-cache, no-transform` to stop supported edge body transformations without allowing third-party or inline code. API messages remain `no-store`. Cloudflare documents the beacon/no-transform interaction at https://developers.cloudflare.com/web-analytics/get-started/ and supported body transformations at https://developers.cloudflare.com/rules/configuration-rules/response-body-inspection/ . Security challenge behavior is controlled upstream and must be assessed separately; no global zone security setting is weakened.

Final activation evidence is recorded in RELEASE-REPORT.md: the dedicated identity, inaccessible home/checkout, read-only release, disabled distribution listener, minimal access logging, nginx validation and public browser flow were verified. The final no-transform response prevented both observed automatic beacon and JavaScript-detection injections, and the public mobile check produced no browser errors. Residual risks and unconfigured external alerting remain as described above.

## Reassessment: 2026-11-22

Scope: all application routers/FFI/OTP state transitions, browser rendering/crypto/invitation/lifecycle code, dependency locks, checks/deployment scripts, active service isolation and this nginx vhost. Review and fixtures stayed separate from public user conversations. Cloudflare's response headers were observed; no zone-wide changes, authenticated Cloudflare configuration audit, other-app probing or host package upgrades were performed.

No critical/high application authorization or code-execution vulnerability was demonstrated in this review. This is a bounded source/configuration review with regressions, not a certificate that none exists.

| ID | Assessment | Resolution and evidence |
| --- | --- | --- |
| R01 | Medium: secondary moderator DOM copies survived message expiry; async report results could populate an obsolete room/dialog. | Expire previews from the current snapshot/deadline; clear dialog state on close/navigation/lock; reject obsolete results by request/generation. Browser regressions reproduce delayed responses and expiry. |
| R02 | Medium: creator burn removed the parent locally while replies remained until another snapshot, especially when paused. | Cascade local parent/reply removal and prune secondary views immediately. Browser test burns a populated thread with updates paused. |
| R03 | Medium: aborting fetch alone did not prevent an already-decoding snapshot from restoring a closed event. | Treat room closure as terminal until an explicit navigation; check that state after asynchronous decoding. Test deliberately suspends decoding until after a live closure notification. |
| R04 | Low hardening: the check server wrote a predictable shared `/tmp/spectre-check.log`, allowing artifact conflicts or precreation; redirection depends on host symlink protections. | Use a private unpredictable mktemp log, quote its path and remove it in the cleanup trap. |
| R05 | Abuse-control gap: owners could remove content but could not restrict new posting. | Owner-only settings, room-scoped questions/pause policies and bounded expiring per-token cooldowns. Tests cover wrong-room/absent/read-only capabilities, actual Retry-After/expiry, capacity exhaustion, owner bypass and live notifications. This does not prevent anonymous token rotation. |
| R06 | Product/privacy defect: poll composer fields crossed room changes; message drafts were lost. | Bounded isolated per-room memory drafts, managed-event cleanup and explicit reload disclosure. Storage/room-switch/closure checks verify no draft/key persistence. |
| R07 | Misleading documentation: SECURITY.md and an architecture sentence still described private rooms/E2EE as unavailable. | Align the current policy and public information with bearer invitations, optional text encryption and explicit metadata/identity/deletion limits. Keep old release reports dated as historical evidence. |
| R08 | Release assurance gap: deployment preview did not exercise browser/a11y flows, and CI lacked current Hex advisory checks. | Check npm/Hex advisories, then exercise all browser, lifecycle and product suites against the exact isolated systemd shipment before switching production. |

Text is still rendered through textContent/DOM nodes; no HTML insertion or remote user embed was introduced. Settings require the event owner's capability, plus private read authorization; an operator moderator cannot take over another owner's settings. Metadata and posting modes cannot change encryption/privacy/discovery/lifetime. All anonymous controls remain bounded and independent cleanup removes cooldowns without incoming traffic.

The active baseline service was `spectre-link`, read-only under /opt with ProtectHome/ProtectSystem/NoNewPrivileges and a 512 MiB limit. Port 4000 was loopback-only; the app's checked-in vhost/proxy matched the active files. npm audit returned no advisories for the locked development tree and OSV returned no matches for 13 locked Hex packages on this date. The new [OSV inventory check](../scripts/audit_hex.py) sends only public package names/versions to [OSV querybatch](https://google.github.io/osv.dev/post-v1-querybatch/); it fails rather than reporting clean if the lookup is unavailable.

Residual risks: bearer-link forwarding, copied plaintext/screenshots, malicious origin/browser code, anonymous poll manipulation/token rotation, public-content abuse, service flooding within/above infrastructure capacity, and memory/log copies beyond logical expiry. No external uptime alert destination, identity verification, independent crypto assessment, infrastructure-retention contract or host-wide vulnerability certification was added. Workspace 3.1 activation evidence is in WORKSPACE-RELEASE.md; the session-tool follow-on below records the later release.

## Session tools follow-on: 3.2

The current additions are covered by SESSION-TOOLS-PLAN.md and SESSION-TOOLS-RELEASE.md. Spotlight is moderator-only; main-question resolution and poll closure require that message's creator capability or room moderation. Private read access is still required, even with the correct creator key. Wrong-room owner/creator capabilities, wrong kinds, reply spotlighting and non-boolean transitions are rejected. Closed-poll votes fail with 409; reopening preserves counts and deadlines. New statuses and spotlight IDs are server-visible metadata; no E2EE or verified-identity claim is extended to them.

Spotlight stores only one message ID per room, bounded by the existing 500 live-message global cap. Independent expiry, burn and room closure remove its pointer. Presentation uses only the current tab's authorized snapshot and renders text through the same safe DOM path; polls are non-interactive there. Tests exercise removal of all secondary presentation/spotlight copies on expiry, local hide, removal, navigation and event closure, including encrypted rooms, mobile, both themes and Romanian. Browser suspension and participant-made copies remain outside logical cleanup guarantees.

The implementation also corrects buffered responses overwriting offline/terminal connection status and makes presentation cleanup synchronous on navigation/lock. Native close events are asynchronous; an old close event is ignored when a presentation has already reopened. These are lifecycle/correctness hardening changes, not newly claimed critical vulnerabilities. Existing app service isolation, scoped proxy, diagnostic redaction, input/rate/capacity limits and public noindex/no-store boundaries are preserved.

Final 3.2.1 evidence is in SESSION-TOOLS-RELEASE.md, including successful remote GitHub CI and the public encrypted-session test. An unpaced public test encountered the existing nginx read burst limit; the paced journey passed without changing protection settings. Shared-IP bursts remain a usability/capacity boundary, not an authentication bypass. A short landscape viewport regression was fixed and covered at 568×320 and 844×390 before final verification.
