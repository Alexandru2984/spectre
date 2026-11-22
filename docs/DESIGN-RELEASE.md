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

The exact compiled 3.3.0 shipment passed the existing isolated systemd deployment gate before activation: 12 unit tests, 175 HTTP checks, all five browser suites, six-page SEO/localization checks, JavaScript syntax, Gleam formatting, npm/Hex advisory lookups and the vendored QR check. The browser journeys cover both themes, RO/EN, encryption, drafts, room/creator/moderator controls, presentation, closure/expiry, mobile/landscape and automated axe checks. nginx validation passed before reload.

- Runtime source: `46fcdfed473a` (later documentation commits do not change runtime files).
- Active shipment: `/opt/spectre-link/releases/46fcdfed473a-20261122T181607Z`.
- Restricted configuration backup: `/var/backups/spectre-link/46fcdfed473a-20261122T181607Z`.
- Previous release/rollback target: `/opt/spectre-link/releases/383a25d93ad0-20261122T134957Z`, version 3.2.1. Follow OPERATIONS.md for rollback; restarting clears ephemeral state.
- Observed service: active, zero automatic restarts and about 45 MiB current memory. Only the app's loopback 4000 listener remains; temporary 4400/4402 are released.

Public checks through Cloudflare/nginx passed for all six EN/RO pages. Public dashboard.js, dashboard.css, i18n.js, icons.svg and social.png hashes match the committed assets; a Romanian room query retains noindex. No observed analytics/challenge injection or CSP relaxation was introduced.

A public browser check created a new private encrypted event and verified the direct room heading, encrypted message submission, closed-by-default prompts, disclosed room tools, presentation and Romanian/light mobile accessibility without horizontal overflow or JavaScript/CSP errors. The owned test event was closed and no existing public conversations were inspected. Actual public captures are `test-results/production-design-desktop.png` and `test-results/production-design-mobile.png`.

The preceding session-tool release is documented in SESSION-TOOLS-RELEASE.md. No Git push or new remote-CI claim is part of this design iteration; commit attribution remains the owner's existing identity without co-author trailers. No skill/package installation or changes to server authorization, persistence, Cloudflare/DNS/tunnels or external notification services were required.
