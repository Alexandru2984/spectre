# Spectre 3.4: reading and browser lifecycle

Date: 2026-11-22. Baseline: 3.3.0. Scope: READING-PLAN.md.

## Behavior

- Reading view hides the composer and gives the conversation a centered, wider column. Writing, reply, N and the mobile shortcut restore the composer without clearing text, poll options, type, lifetime or reply context.
- The mobile shortcut appears when neither the composer nor the reading-view writing control is visible. It does not cover the restore controls just because the composer is hidden.
- A hidden-message notice remains available while other messages are visible. Undo restores the most recent hide; show-hidden restores only the current room's still-live choices. Hiding a parent still hides its replies. Restoration cannot extend lifetime or revive expired messages. Keyboard focus moves to a usable control after hide/restore.
- Constellation excerpts, hit objects and pixels clear when inactive, empty, expired, navigated away from or locked. Message/share/moderator/settings/report/delete/presentation dialog cleanup is synchronous on app dismissal and Escape, with protection against queued native close events erasing a reopened dialog.
- Late report, creator-delete and settings responses cannot dismiss or write errors into a newer dialog. Successful current-room server changes remain reflected in the authorized snapshot.
- A late event-closure response cannot lock a different room or clear that room's draft. Repeated close submissions are disabled until the request finishes; actual event closure still reaches its participants.
- New controls and public information are available in EN/RO and both themes. No package, skill, persistent content store or external vendor is added.

## Targeted verification

The new browser reading/lifecycle journey reproduced the retained constellation excerpts before the fix. It now covers inactive pixels/excerpts, empty-room navigation, TTL expiry, immediate dialog clearing, native close/reopen races, held real mutation responses, draft fields, writing entry points, room-scoped undo/restore and expired hidden entries. It also checks no conversation/key/hide data enters browser storage.

Reading controls were checked at 1440×1000, 320×844, 390×844, 768×844 and 568×320 with EN/RO, both themes, no horizontal overflow and no automated axe WCAG A/AA violations. Visual captures in ignored `test-results/reading-1440.png` and `reading-390.png` use local synthetic content. Existing lifecycle/session journeys passed after cleanup changes. Full compiled-shipment and production observations will be recorded after the release gate; these local results do not imply deployment or remote CI.
