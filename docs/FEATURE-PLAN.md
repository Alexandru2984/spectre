# Spectre 3: complete feature delivery plan

Requested: implement the entire proposed feature package, then work on SEO separately. Preserve owner author/committer identity, with separate stage commits and no AI/co-author attribution. Existing production remains on its immutable release while development and checks use isolated ports.

## Scope and sequence

1. Consolidate room/message authorization and mutation into one bounded OTP coordinator behind the Gleam HTTP boundary. Deliver ephemeral threaded replies, 2–6 choice polls (one mutable selection per anonymous page token), reports, local hiding and moderator removal. Child deadlines may never outlive their parent; removal cascades.
2. Managed rooms: explicit owner capability, 15/30/60 minute event lifetime, early closure, opt-in public discovery, private read capabilities, optional pseudonyms and bounded heartbeat presence. Built-in public rooms remain. Managed rooms receive reserved random IDs so expired private IDs cannot fall back to unprotected public rooms.
3. Immediate room updates using bounded asynchronous long polling: return on room revision change, hold at most 20 seconds, cap watchers globally/per address/per room, clean disconnected waiters, reconnect with backoff and retain a snapshot fallback. Private access is carried in headers, never query strings. Event expiry and access checks happen server-side.
4. Complete responsive browser flows for threads/polls/reporting/moderation, room creation/discovery, participants/pseudonyms/event timers and closures. Add local QR invitation generation, translated daily prompts/challenges and RO/EN across controls, dialogs and errors. Keep user content outside translation logic.
5. Private-room content encryption using the browser's AES-256-GCM Web Crypto API, a fresh 96-bit IV per message, room-bound authenticated data, and keys shared only in URL fragments. Separate read, moderation and encryption keys. The server stores ciphertext and bounded metadata; never send the encryption key to an API. Encrypt poll text/options and replies as well. No encrypted-room claim for public or merely access-controlled rooms.
6. Extend unit, HTTP, browser, authorization, expiry, crypto, translation and mobile/accessibility checks. Exercise two independent browser contexts for live updates, access denial, poll behavior and encryption. Export and test the exact compiled release under the service identity before deployment.
7. Deploy only this service/vhost, preserve previous release/rollback, verify the public flow in a new temporary room, close that room, record evidence and remaining limits. Do not claim GitHub-hosted CI ran without a push. Defer additional SEO work until this package is complete.

## Security review

Top risks: unauthorized private-room reads/mutations; expiry or closure retaining thread/poll/session/report content; anonymous room/subscriber/report resource exhaustion. All ACL checks and mutations use a single coordinator state to avoid check/use races. Cap rooms, messages, replies, voters, participants, reports and long-poll waiters. Reject unsupported JSON, controls, oversized bodies, invalid indices, expired parents and cross-room references.

Access and moderator tokens are random 192-bit capabilities; store only hashes. Discovery never lists private or unlisted rooms. Generated room IDs remain protected even after expiration (unknown reserved IDs fail closed). Room closure destroys messages, votes, presence and reports and wakes watchers. No account, persistence, remote QR service or analytics vendor is introduced. Built-in moderation uses an operator secret in a root-owned environment file, outside Git and HTTP logs.

Encryption protects message/poll/reply text against passive server-side content access, not against a compromised browser, malicious origin JavaScript, copied invitations, screenshots, or traffic/room/presence metadata analysis. A participant with the shared key can read and author content; aliases and anonymous votes are not verified identities. A server compromise affects active metadata/ciphertext and moderation secrets; exact user counts and monetary impact are unknown, not invented. The existing incident runbook applies: isolate this service, revoke room/operator capabilities, investigate accessible data, deploy a reviewed release. Current external alert destination and regulatory applicability remain operator decisions; no new compliance claim is made.

## Acceptance

- Complete flows for every row in the proposal: replies, polls, presence/aliases, immediate updates, moderation, discovery, timed event rooms, QR sharing, daily challenges, RO/EN; plus private invitations and E2EE.
- Parent burn/expiry and room closure remove dependent data without client polling.
- Private read/write/react/vote/report/presence/watch/discovery checks cannot be bypassed with another room's ID/key. Creator/moderator rights are distinct from read rights.
- Ciphertext is the only message/poll text sent/stored for encrypted rooms; wrong keys fail visibly; raw keys never enter API URLs/logs/browser persistent storage.
- EN/RO does not translate user messages; no unsafe HTML rendering or CSP relaxation.
- Desktop/mobile/keyboard/reduced-motion flows and existing product behavior remain usable. No user-content test payloads in existing production rooms.
