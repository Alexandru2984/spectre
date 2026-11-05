# SEO follow-on

Feature package completed and verified before this stage. Scope: useful public content and discoverability, without indexing conversations or changing room/privacy boundaries.

- Six independently rendered public URLs: English homepage/about/privacy and Romanian /ro, /ro/about, /ro/privacy. Romanian content must be present without JavaScript, with correct lang and matching title/description.
- Self-canonical URLs; reciprocal EN/RO/x-default alternates; sitemap containing only the six public pages. No invitation/message/room URLs in metadata, structured data or sitemap.
- Accurate feature-focused public copy and internal navigation. Explain public vs private and optional encryption without claims of perfect secrecy or fake user/review numbers.
- WebSite structured data on the homepage and WebPage descriptions of informational pages. Do not fabricate ratings or claim rich-result eligibility.
- Localized Open Graph/Twitter metadata using existing local social image, with appropriate alt text.
- Preserve CSP, no-transform, no-store APIs and noindex room query URLs in both languages.
- Deterministic locale generation checked in CI; HTTP/browser/axe checks for both languages and client language switching that preserves in-memory room keys.

Reference: Google Search Central localized versions, canonical URLs and site-name documentation. No Search Console ownership token, sitemap submission, analytics integration or ranking promise is implied. Existing edge bot policies remain unchanged.
