# Changelog

## v2.3.4 — 2026-10-19

- Honor the auto-title setting in chats and Ship conversations, preserve manually chosen titles, and show saved titles in Ship history.

## v2.3.3 — 2026-10-19

- Align setup instructions and provider descriptions with separate LM Studio and Other Servers settings.
- Add a dedicated update guide and document GitHub update requests, reset limits, and source-only Apple Intelligence availability.
- Correct About links and qualify local-processing descriptions; refresh website and portfolio feature summaries.

## v2.3.2 — 2026-10-19

- Sparkle update checks, a Check for Updates menu item, and a General settings toggle. Installations always require approval.
- Signed update feeds and packages published with notarized releases; release build numbers now follow the app version.
- Existing v2.3.1 users need one manual upgrade to receive in-app updates.

## v2.3.1 — 2026-10-19

- Separate LM Studio and Other Servers settings with independent forms and existing connection preservation.
- Official Get links, setup guides, and a build-aware Apple Intelligence explanation with an Xcode App Store link.
- Searchable knowledge base linked from the website, Help menu, provider settings, and Getting Started.

## v2.3.0 — 2026-10-19

- Delete confirmations, an optional five-minute pause for chat confirmations, and a typed full-data reset in General settings that finishes at the next launch. Reset removes the store, app preferences/cache, and app-owned Keychain credentials; external files, backups, provider copies, and local model installations are unaffected.
- Correct Keychain/storage wording and prevent late chat responses from writing into deleted conversations or Ships.

- Clearer first-chat onboarding and Ship setup, with plain-language tabs, missing-field guidance, and collapsed advanced model settings.
- Collapsible Chats with five recent conversation groups, selected-chat visibility, and searchable full history.
- Simplified sailboat branding, a native modern macOS Dock icon, and an appearance-aware in-app mark for light and dark mode. Older SDK builds retain the legacy asset catalog icon.

- Separate harbors for Personal, Work, and other areas. Create, rename, switch, and move chats, Ships, and brainstorms. Existing data belongs to Personal. Chat forks and Ship history move together; provider settings stay shared.
- Interactive Getting Started guide with highlights on the real controls, saved progress, Back/Skip, model-connection readiness, and a first-chat step. Settings and Ship setup keep the guide in place; only Finish tour marks it complete. Help always reopens it.
- A plain-language explanation beneath Build your first Ship.

### Local models and reliability

- LM Studio setup preset, editable endpoint address, and separate welcome-page connection status. Ollama and LM Studio can run every brainstorm role locally with downloaded on-device models.
- Welcome and Settings share provider-group counts. Failed endpoint discovery clears stale models.
- Token accounting across chat, Ships, comparisons, brainstorming, and follow-up Q&A. Unknown counts stay unknown; estimates are identified; cache and reasoning subsets are not counted twice.
- Leaner brainstorm context: older contributions are shortened, and follow-up Q&A reuses the decision brief while retaining the full stored transcript and exports. No fixed token-savings percentage is promised.
- Welcome layout, geometry handling, compiler-warning cleanup, and version-label fixes.
- Reliable release stapling over HTTPS/TCP, plus manual release retries for existing version tags.

Published downloads and their exact contents are listed in [GitHub Releases](https://github.com/d-edgar/ChatHarbor/releases). A successful source build does not mean a new signed and notarized release has published.
