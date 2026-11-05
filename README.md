# Spectre · Spectre-Link

A public space for fleeting thoughts, built with Gleam and Erlang/OTP. Try it at **https://spectre.micutu.com**.

Share a thought, idea or question in a public room. Choose a lifetime, react while it is here, and watch it disappear. No account or message database. Every message is an OTP actor, backed by a bounded registry with independent expiry.

## Features

- Public rooms: lobby, ideas, questions, after-hours and named rooms with shareable links.
- Thoughts, ideas and questions, with 15s / 30s / 1m / 5m lifetime presets (API: 3–300s).
- Live feed and interactive constellation; local search, category/mine filters and sorting.
- Three toggleable reactions with one selection per page token and message.
- Creator-only early burn using a random capability, kept only in the current page's memory.
- Live countdowns, pause/resume updates, network recovery and clock-skew compensation.
- Light/dark themes, keyboard shortcuts, reduced motion and responsive mobile layout.
- Local assets, strict CSP, validated UTF-8 JSON, separate read/write limits, bounded rooms/messages/reactions.
- Public about/privacy pages, metadata, social preview, sitemap and room/API noindex headers.

**All rooms are public.** Knowing a room name is not authentication. Messages are not end-to-end encrypted. The timer does not prevent copies/screenshots, remove infrastructure logs, or guarantee physical erasure of memory. Closing or reloading loses your burn controls. See [privacy](https://spectre.micutu.com/privacy) and the [security audit](docs/SECURITY-AUDIT.md).

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

All message reads are scoped to a public room; omitted `room` defaults to `lobby`. Responses containing messages are `no-store` and `noindex`. `X-Server-Time` supplies the server clock in milliseconds. All mutation bodies require `Content-Type: application/json` and a bounded Content-Length; cross-origin browser writes are rejected. No CORS access is granted.

| Method | Path | Request / response |
| --- | --- | --- |
| GET | `/api/messages?room=lobby` | Array of active messages in that room |
| POST | `/api/messages` | `{"content":"Hello","ttl":30000,"room":"lobby","kind":"thought"}` → `id`, `burn_key`, `message` |
| POST | `/api/messages/:id/reactions?room=lobby` | `{"emoji":"spark"}`; header `X-Spectre-Client`: 48 lowercase hex characters. Choices: `spark`, `heart`, `curious`; selecting again toggles off. |
| DELETE | `/api/messages/:id?room=lobby` | Header `X-Burn-Key`: returned creator capability. Never put it in a URL. |
| GET | `/api/stats?room=lobby` | Active count and room/lifetime limits |
| GET | `/api/nodes` | Compatibility alias list `["local"]`; no internal node names |
| GET | `/healthz` | Minimal liveness status |

Content: 1–500 graphemes, at most 2000 UTF-8 bytes, no unsupported control characters. Room names: 1–32 lowercase ASCII letters/numbers/hyphens, first character alphanumeric. Max 100 active messages per room, 500 globally, 256 reaction tokens per message. Application write budget: 30/min/client and 600/min globally; reads use a separate budget. Proxy limits and shared NAT addresses can also affect clients. A 429 includes Retry-After; capacity returns 503. Anonymous reaction tokens deter accidental duplicates, not determined vote manipulation.

## Architecture and operations

```text
Browser → Cloudflare → nginx → loopback Mist HTTP server
                                   ├── rate-limit actor (bounded minute windows)
                                   └── registry actor (bounded, room-scoped)
                                        └── message actors + expiry timers
```

Critical actors are linked to the application entry process. A critical failure exits the instance; systemd restarts an empty instance rather than persisting message content. Expiry uses monotonic deadlines on the server; public timestamps use wall-clock time. No claim of durable delivery, private rooms, distributed replication or automatic hot upgrades is made.

[Operations and rollback](docs/OPERATIONS.md) · [Audit](docs/SECURITY-AUDIT.md) · [Roadmap](docs/ROADMAP.md). Run `./scripts/deploy.sh` only on the configured VPS from a clean committed checkout. It tests a root-owned release under a dedicated systemd identity before switching this application's service/vhost. Restarts clear all live content.
