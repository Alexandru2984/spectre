# Reading and browser lifecycle improvements

Baseline: 3.3.0 (`46fcdfed473a`), 2026-11-22. Keep the simplified room-first design and existing EN/RO routes, themes and server authorization.

## Verified issues to address

1. Leaving constellation view retains its hidden signal buttons, canvas pixels and message hit objects. Emptying the view can leave the last drawing behind. Clear all three when the view becomes inactive, empty or unavailable.
2. Native dialog close events are asynchronous. Unconditional cleanup can erase a newly reopened dialog. Clean explicit dismissals synchronously and ignore stale close events while a dialog is open. Bind report, delete and settings responses to the dialog invocation that started them.
3. Conversation focus currently leaves the composer visible. Make it a real reading view with a wider stream and an explicit route back to writing. Preserve drafts and restore the composer for replies, keyboard shortcuts and mobile writing.
4. Hidden messages have no restore action while other messages remain visible, and the empty-state restore action uses a global hidden-message collection. Add a room-scoped notice, undo the most recent hide, and restore only current-room messages that are still alive.

## Delivery

- Commit this plan, then each verified implementation stage using the repository owner's existing identity without additional attribution.
- Add browser regressions for stale dialogs, canvas cleanup, asynchronous responses, reading/draft navigation and room-scoped hiding. Exercise both themes, EN/RO and small screens; retain encryption/expiry coverage.
- Run the existing deployment gate plus the new browser journey against the isolated compiled shipment. Bump the release version, update operational/security/product documentation, activate the verified build and inspect only owned public test rooms.
- Do not install dependencies, persist conversation content or keys, change infrastructure policy, push Git commits or inspect existing public conversations for these changes. Record actual test and rollout evidence separately from planned work.

## Later product work

Prioritize useful session workflows over extra chrome: clearer participant onboarding, better poll/result navigation and keyboard discovery. Keep server-side abuse limits and ephemeral retention as release constraints. Review SEO and CI after the user-facing flows are verified; remote CI needs a pushed revision and is not implied by local checks.
