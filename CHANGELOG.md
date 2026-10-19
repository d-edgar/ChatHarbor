# Changelog

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
