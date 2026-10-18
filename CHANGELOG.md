# Recent development

## Unreleased — source implementation

- Clearer first-chat onboarding and Ship setup, with plain-language tabs, missing-field guidance, and collapsed advanced model settings.
- Collapsible Chats with five recent conversation groups, selected-chat visibility, and searchable full history.
- Simplified sailboat branding, a native modern macOS Dock icon, and an appearance-aware in-app mark for light and dark mode. Older SDK builds retain the legacy asset catalog icon.

- Separate harbors for Personal, Work, and other areas. Create, rename, switch, and move chats, Ships, and brainstorms. Existing data belongs to Personal. Chat forks and Ship history move together; provider settings stay shared.
- Four-step first-launch tour with Back, Next, Skip, remembered dismissal, Help → Getting Started, and a shortcut to model setup.
- A plain-language explanation beneath Build your first Ship.

## Recent source changes — not a new release announcement

- LM Studio setup preset, editable endpoint address, and separate welcome-page connection status. Ollama and LM Studio can run every brainstorm role locally with downloaded on-device models.
- Welcome and Settings share provider-group counts. Failed endpoint discovery clears stale models.
- Token accounting across chat, Ships, comparisons, brainstorming, and follow-up Q&A. Unknown counts stay unknown; estimates are identified; cache and reasoning subsets are not counted twice.
- Leaner brainstorm context: older contributions are shortened, and follow-up Q&A reuses the decision brief while retaining the full stored transcript and exports. No fixed token-savings percentage is promised.
- Brainstorm shortlists, a disagreement pass, decision notes, outcomes, and Markdown/PDF exports.
- Welcome layout, geometry handling, compiler-warning cleanup, and version-label fixes.

Published downloads and their exact contents are listed in [GitHub Releases](https://github.com/d-edgar/ChatHarbor/releases). A successful source build does not mean a new signed and notarized release has published.
