# Spectre: product completion and security review

Review date: 2026-11-22. Baseline: `365cabd`. Scope: this repository, this application's release, service and nginx configuration. Existing user work is clean; the branch already contains four unpublished commits. Preserve that history and do not push automatically.

## Evidence and priorities

The current product is Gleam/Erlang with local JavaScript/CSS, not React. It already supports public/private events, optional AES-GCM content encryption, polls, reactions, live notifications, reports and English/Romanian public pages. Replacing the stack adds risk without addressing the product's gaps.

Baseline checks passed: nine Gleam tests, 69 HTTP checks, 42 feature/authorization checks, desktop/mobile browser journeys and automated axe checks. npm audit returned zero advisories; OSV querybatch returned zero matches for the 13 locked Hex packages on the review date. Negative lookups are not a guarantee of security. The public HTML returns CSP, framing restrictions, no-referrer, HSTS and nosniff. The service is isolated under `spectre-link`, binds loopback and runs a separate root-owned shipment. The checked-in vhost/proxy match the active files. No restart was needed for inspection; no public message content was read.

| Finding | Priority | Action |
| --- | --- | --- |
| Moderator results can retain visible message copies after expiry/room closure; asynchronous dialog responses are not scoped to navigation. | Medium, privacy/correctness | Expire/redact secondary DOM copies; abort or ignore obsolete dialog requests; clear sensitive dialog state on close, navigation and lock. |
| Creator burn removes only the parent from the local message list until the next snapshot. Paused clients retain dependent replies. | Medium, privacy/correctness | Immediately cascade local removal; apply server snapshots to moderation and selected-message views. |
| Thread buttons open only the parent, leaving replies out of the conversation view. | Product defect | Render accessible chronological replies and preserve keyboard focus. |
| Composer options leak across room changes while message drafts are discarded. | Product defect | Keep bounded per-room drafts only in page memory; clear on expiry/closure/restart. |
| Tiny 8–12px controls and sprawling introductory decoration push the primary task down the page. | Accessibility/usability | Redesign around the room, readable typography, clear controls and mobile navigation. |
| Owners can remove content but cannot pause posting or apply a room cooldown. | Abuse/product gap | Server-enforced owner settings, bounded per-token cooldowns, explicit limits and cross-room authorization tests. |
| Existing test/deploy tooling uses a predictable shared `/tmp` log; deploy does not run the browser suite. | Operational hardening | Use private temporary files and make exact-release checks explicit. |

## Delivery stages (one commit per verified stage)

1. Record this review and acceptance plan.
2. Correct privacy/lifecycle defects and harden temporary check artifacts; add regression coverage for the actual failures.
3. Add owner-managed room topic, pause and slow mode, with API authorization and bounded ephemeral state. Add useful event presets, topic visibility, complete threads, unanswered questions, per-room memory drafts and room navigation.
4. Deliver a cohesive responsive redesign: compact masthead, functional room workspace, readable cards, accessible controls and a mobile composition shortcut. Keep both themes and both languages complete.
5. Finish with SEO/CI checks, expanded browser/security journeys, release documentation and a scoped preview-before-switch deployment. Verify the public release and leave a clean committed checkout. All commits use the owner's existing identity with no assistant/co-author attribution.

## Acceptance

- Owner controls require that room's capability; participant and unrelated-room capabilities cannot change settings. Private read authorization remains mandatory.
- Posting pause and cooldown are enforced on the server; cooldown state has fixed capacity and independent expiry. Anonymous tokens do not identify people or prevent deliberate token rotation.
- Thread messages, moderator previews and replies vanish on expiry/removal/room closure. Obsolete async responses cannot restore another room's UI content.
- Drafts and capabilities never enter localStorage/sessionStorage, URLs, analytics or logs. At most a bounded number of room drafts remain in page memory, and managed-room expiry purges them.
- At 320/360/390/768px and desktop, forms/dialogs do not overflow; controls remain readable and keyboard accessible. No script/HTML execution from user text.
- Both languages, both themes, encrypted polls/replies and live closure continue working. Unit, HTTP and browser checks run against an isolated compiled shipment.
- Deployment affects only this app. A restart clears live ephemeral messages/events; no content backup is created. Rollback retains the previous release.

## Further product work

After observing real use: opt-in browser notifications, accessible presentation mode for workshops, room-specific moderation queues, an operator-owned uptime alert destination, and privacy-preserving aggregate performance measurements. Push notifications, accounts, persistent history, uploads, analytics vendors and distributed replication require their own retention/access design; they are not silently introduced here. Search Console setup and actual indexing/rankings require operator-owned access and observation.

This is a source/configuration review plus bounded tests, not an independent penetration test, host-wide compromise investigation or cryptographic certification. Traffic flooding, participant screenshots, malicious invitation holders, anonymous vote manipulation and infrastructure retention remain explicit limits.

## Completion evidence

All five delivery stages are complete for this iteration. WORKSPACE-RELEASE.md records the shipped behavior, exact local/preview/public checks, active source/release, backup, rollback target and remaining external measurement work. The new 3.1 runtime is active at https://spectre.micutu.com. CI is configured and passed locally; no remote GitHub run is claimed without a push.
