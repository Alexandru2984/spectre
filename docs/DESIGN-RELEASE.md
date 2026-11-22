# Spectre 3.3: room-first interface

Date: 2026-11-22. Baseline: `95a2987`, with 3.2.1 active. This iteration responds to the request for a less generic, less promotional design.

## Changed

- The actual room name is the page's main heading. The introductory slogan/fact block and decorative sidebar quotation are removed.
- Main messages read as a flat conversation list. Reply indentation, lifetime indicators, polls, creator controls and moderation retain their existing behavior.
- Message labels and feedback use direct language: Send message, Delete message, No messages yet, and Search messages. About/help/privacy copy and the share image follow the same style.
- Conversation prompts remain available in a native disclosure below the composer, closed by default. They no longer occupy a full row above the primary task.
- Presentation/moderation/owner actions are grouped under Room tools. The native disclosure supports keyboard focus, Escape, outside-click dismissal and modal focus restoration. Participant/discovery actions remain directly visible. This is UI grouping, not an authorization boundary.
- Room navigation shows the authorized room name rather than the generated room ID. Connection dots remain for real connection state; the static current-room dot was removed. A single active session uses correct singular wording.
- The Spectre mark, established palette, both themes, EN/RO routes and existing features remain. No skill, framework, runtime package or design vendor was installed. The Sites skill consulted in the conversation was already available.

## Local review

The existing core, encrypted two-browser, lifecycle, product and session browser journeys passed with the updated labels and disclosed controls. Existing SEO/localization and JavaScript syntax checks passed. A separate visual review verified the open tools disclosure at 320/390/768px with no horizontal overflow and no axe WCAG A/AA violations, exercised optional prompts and closed its synthetic private event. The sample 390×844 owner view placed the composer at about 429px from the top, with prompts closed.

Ignored review artifacts under `test-results/`: `design-before-desktop.png`, `design-before-mobile.png`, `design-desktop-dark.png`, `design-desktop-light.png` and `design-mobile.png`. Samples use locally created test content, not existing production conversations. Visual style is reviewable in these captures rather than represented as an automated aesthetic score.

## Publication

The compiled-shipment verification, active release, rollback paths and public checks are recorded here after the existing isolated systemd deployment gate completes. The preceding session-tool release is documented in SESSION-TOOLS-RELEASE.md. No Git push is implied; commit attribution remains the owner's existing identity without co-author trailers.
