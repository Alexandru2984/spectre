# Spectre 3 · Spectre-Link

A public space for fleeting thoughts, built with Gleam and Erlang/OTP. Try it at **https://spectre.micutu.com**.

Share a thought, idea or question in a public room. Choose a lifetime, react while it is here, and watch it disappear. No account or message database. Every message is an OTP actor, backed by a bounded registry with independent expiry.

## Features

- Public rooms and 15/30/60-minute managed events with topics, explicit opt-in discovery and owner closure.
- Invitation-only private events, optionally with browser AES-256-GCM content encryption. Read, owner and encryption keys are separate; only participant keys appear in fragment invitations.
- Thoughts, ideas, questions, threaded replies and 2–6 choice polls. Replies never outlive the parent; removing a parent/event removes dependants.
- Three reactions, mutable anonymous poll selections, creator burn, local hide/restore, reason-based reports and capability-protected moderation.
- Bounded live revision notifications, snapshot fallback, optional room aliases, session presence, event timers and daily prompts.
- Local QR invitations, feed/constellation/search/filter/sort, full RO/EN controls/help/errors/information pages, mobile layout, themes, keyboard support and reduced motion.
- Strict CSP, local assets, bounded OTP memory, origin/framing validation, independent expiry and dedicated read-only production identity.

Public room names do not authorize access. Private invitations grant access to anyone holding them; optional E2EE protects content rather than metadata, screenshots, malicious browsers or malicious origin code. There are no authenticated identities, per-person revocation, key recovery or forward secrecy. The timer does not guarantee physical erasure. Closing/reloading loses unsaved invitation/owner/burn controls. See [privacy](https://spectre.micutu.com/privacy), [feature threat model](docs/FEATURE-PLAN.md) and [operations](docs/OPERATIONS.md).

## Local development

Requires Gleam 1.16+, Erlang/OTP 27+, Rebar3 3.26. Node 24, npm and Python 3 are used only for checks.

```sh
PORT=4400 ./run.sh
# http://127.0.0.1:4400
```

Do not start a second development instance on port 4000 on the production VPS. `./run_peer.sh` uses 4401; its registry is independent. Distributed Erlang is disabled; connecting BEAM nodes does not replicate messages.

## Checks

```sh
npm ci --ignore-scripts
npx playwright install chromium
./scripts/check.sh
```

Use `npx playwright install --with-deps chromium` on a fresh Linux CI machine. Port 4400 must be free. The check script builds a shipment and tests that exact release with Gleam unit tests, HTTP regressions, browser flows and automated axe WCAG A/AA checks. Browser screenshots go to ignored `test-results/`. Automated checks do not replace a full manual accessibility audit or an independent pentest.

## API

All message reads are scoped to a room; private rooms require X-Room-Key, and omitted `room` defaults to `lobby`. Responses containing messages are `no-store` and `noindex`. `X-Server-Time` supplies the server clock in milliseconds. All mutation bodies require `Content-Type: application/json` and a bounded Content-Length; cross-origin browser writes are rejected. No CORS access is granted.

| Method | Path | Request / response |
| --- | --- | --- |
| GET | `/api/messages?room=lobby` | Array of active messages in that room |
| POST | `/api/messages` | `{"content":"Hello","ttl":30000,"room":"lobby","kind":"thought"}` → `id`, `burn_key`, `message` |
| POST | `/api/messages/:id/reactions?room=lobby` | `{"emoji":"spark"}`; header `X-Spectre-Client`: 48 lowercase hex characters. Choices: `spark`, `heart`, `curious`; selecting again toggles off. |
| DELETE | `/api/messages/:id?room=lobby` | Header `X-Burn-Key`: returned creator capability. Never put it in a URL. |
| GET | `/api/snapshot?room=lobby` | Atomic room metadata, messages and presence |
| POST | `/api/rooms` | `name`, `topic`, `minutes` (15/30/60), `private`, `encrypted`, `discoverable` → room, owner_key, access_key |
| GET | `/api/rooms` | Built-ins and opted-in public events; never private/unlisted rooms |
| GET / DELETE | `/api/room?room=:id` | Room metadata / owner-only closure |
| GET | `/api/events?room=:id&since=:revision` | Immediate change notification, bounded hold ≤20s |
| POST / GET / DELETE | `/api/presence?room=:id` | Heartbeat with optional alias / counts and aliases / leave |
| POST | `/api/messages/:id/vote?room=:id` | `{"option":0}` with X-Spectre-Client; one mutable choice per page token |
| POST | `/api/messages/:id/report?room=:id` | `reason`: spam/harassment/sensitive/other, requires page token |
| GET | `/api/reports?room=:id` | Room moderator-only reports; X-Moderator-Key required |
| GET | `/api/stats?room=lobby` | Active count and room/lifetime limits |
| GET | `/api/nodes` | Compatibility alias list `["local"]`; no internal node names |
| GET | `/healthz` | Minimal liveness status |

Content: 1–500 graphemes, at most 2000 UTF-8 bytes, no unsupported control characters. Room names: 1–32 lowercase ASCII letters/numbers/hyphens, first character alphanumeric. Max 100 active messages per room, 500 globally, 256 reaction tokens per message. Application write budget: 30/min/client and 600/min globally; reads use a separate budget. Proxy limits and shared NAT addresses can also affect clients. A 429 includes Retry-After; capacity returns 503. Anonymous reaction/poll tokens deter accidental duplicates, not determined vote manipulation. New-message fields include optional parent_id, author and options (poll only). Private requests require X-Room-Key on every scoped read/mutation/watch/presence path. Moderator removal uses DELETE message with X-Moderator-Key; owner capabilities never appear in discovery or participant invitations. Encrypted posts contain an AES-GCM envelope in content and only generic placeholder options. Refer to FEATURE-PLAN.md and the browser crypto implementation for the protocol; do not put capabilities in query strings.

## Architecture and operations

```text
Browser → Cloudflare → nginx → loopback Mist HTTP server
                                   ├── rate-limit actor (bounded minute windows)
                                   └── registry actor (bounded, room-scoped)
                                        └── message actors + expiry timers
```

The coordinator and rate limiter are linked to the application entry process. The coordinator serializes read authorization, mutations and expiry; OTP status/termination diagnostics redact content, capabilities and queued request details. Encrypted content is decrypted only by the browser. Critical actors are linked to the application entry process. A critical failure exits the instance; systemd restarts an empty instance rather than persisting message content. Expiry uses monotonic deadlines on the server; public timestamps use wall-clock time. No claim of durable delivery, private rooms, distributed replication or automatic hot upgrades is made.

[Operations and rollback](docs/OPERATIONS.md) · [Audit](docs/SECURITY-AUDIT.md) · [Roadmap](docs/ROADMAP.md). Run `./scripts/deploy.sh` only on the configured VPS from a clean committed checkout. It tests a root-owned release under a dedicated systemd identity before switching this application's service/vhost. Restarts clear all live content.
