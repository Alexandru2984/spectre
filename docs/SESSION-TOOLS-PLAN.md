# Live session tools: 3.2 delivery plan

Date: 2026-11-22. Baseline: `ddbabd2`, with the verified 3.1 shipment active. Scope remains this application and its existing deployment path. Preserve the ten already-unpublished commits and use the repository owner's established identity with no co-author/assistant attribution. Do not push automatically.

## Outcome

Make temporary rooms useful to facilitate a workshop or Q&A: shared spotlight, explicit question resolution, host/creator poll closure and a readable presentation view. Keep ordinary participant flows small and both languages/themes accessible.

## Delivery stages

1. Record acceptance and trust boundaries, inspect the clean baseline.
2. Add authorized server state transitions and regressions. Commit after unit/HTTP checks.
3. Add live participant/host controls, spotlight, resolution filters and presentation with keyboard navigation. Verify desktop/mobile, localization, encrypted rooms and lifecycle cleanup; commit.
4. Finish with public information/SEO, CI/deployment coverage, full compiled-release checks and a scoped preview-before-activation rollout. Record the actual release and rollback evidence in a final documentation commit.

## Authorization and lifetime

- Spotlight requires the room's existing moderation capability and private read access where applicable. Only a live top-level message from that room can be highlighted. There is one message ID per room, not another content copy. At most 500 rooms can have a spotlight because the global live-message cap is 500. Removal, independent expiry and room closure clear the pointer and notify participants.
- A live top-level question can be resolved/reopened by its creator's burn capability or that room's moderator. A reply does not by itself certify an answer. The unresolved filter follows the explicit status; reopening brings a question back even if it has replies.
- A live poll can be closed/reopened by its creator or room moderator. Closing freezes votes server-side, including votes from an already-loaded stale client. Counts remain visible until normal message expiry. Reopening never extends lifetime.
- Status flags and the spotlight message ID are server-visible metadata, including in encrypted rooms. Message/option ciphertext and separate invitation/encryption/owner keys retain the existing protocol and limits.
- All transitions are serialized by the same coordinator. Invalid/unauthorized requests allocate no extra state. No public response exposes creator capabilities or raw participant tokens.
- Presentation uses the same authorized in-memory snapshot in the current tab. It does not create another URL, persistent copy, public export or third-party integration. It removes expired content and closes on navigation/room lock; it respects local hides, reduced motion and live pause.

## Acceptance checks

Unit/HTTP: correct/missing/wrong-room keys, private-read requirement even with a valid creator key, wrong message kinds, child-message spotlight rejection, invalid booleans/types, closed-poll vote rejection, reopen/count preservation, room isolation, live revisions, unchanged TTL/deadline and independent spotlight cleanup.

Browser: two participants see spotlight/status/poll transitions; complete encrypted messages remain encrypted on transport; stale UI cannot vote in a closed poll; explicit resolve/reopen drives the unresolved filter. Presentation offers previous/next, filters, direct spotlight access, useful empty states and keyboard operation. Expiry/burn/hide/closure remove every presentation/spotlight copy. Check 320–1440px, both themes, EN/RO and automated axe checks. Existing product/lifecycle suites must continue passing with the intentionally updated filter semantics.

No persistent accounts/history, uploads, remote notifications, analytics vendor, operator alert destination or Cloudflare/DNS setting is introduced. External alert delivery and Search Console still require the operator's destination/account; they do not block this product stage.
