# Regression checks

Run from the repository root with the full Xcode toolchain selected:

```sh
bash Tests/run.sh
```

The checks cover:

- Harbor assignment and moves, interactive tour progress, deletion guards and full-reset behavior using disposable stores.
- Provider usage parsing and totals across chat, Ships, compare, brainstorms, and Q&A.
- Endpoint credentials moving from legacy preferences to Keychain, including a failed migration that must preserve the original settings. The test substitutes an in-memory credential store and does not touch real API keys.
- Endpoint-specific routing, ambiguous old selections, and credential updates/deletion.
- HTML escaping, offline export policy, unknown-price labels, and complete PDF pagination.
- Shortlist and decision-note persistence after reopening a SwiftData store.
- Framing feedback, Round Robin context, shortlist evaluation, disagreement prompts, and exports.
- Switching sessions during Q&A and ignoring responses delivered after cancellation.

The core checks also work with Command Line Tools alone:

```sh
bash Tests/run.sh --core-only
```

The pull-request workflow builds the app without signing and runs all regression checks. SwiftData tests require Xcode's compiler macros. They do not test migration from an older installed app's database.

## PDF pagination

The full suite includes PDF pagination. To run it separately:

```sh
xcrun swiftc ChatHarbor/Services/BrainstormReport.swift Tests/PDFSmoke.swift -o /tmp/chatharbor-pdf-smoke
/tmp/chatharbor-pdf-smoke
```

It exports a long report and checks that the PDF has multiple pages and contains its final paragraph.

Before release, also check an upgrade with an existing database, the visible shortlist and decision-note editors, provider streaming, and the rendered PDF layout in the app.

Local verification: core regression checks and the five-page PDF test passed. The full app build and SwiftData checks remain pending in an Xcode environment.

## First-chat and Ship setup UI checks

Before release, verify these in the built app (the regression suite does not drive SwiftUI):

- With no models, the tour and welcome screen offer **Connect a model** and open Models & Providers. Opening settings from step one leaves the tour incomplete.
- With a model available, **Start a chat** opens a regular conversation in the selected harbor. If the previously selected model is unavailable, it selects an available model.
- Skip remains available, Back works, and Help reopens the tour. Starting a chat from the tour marks it complete.
- The Ship builder names its tabs Identity, Model, Instructions, Knowledge, and Response Rules. Missing name/model guidance navigates to the relevant tab; whitespace-only names cannot be saved.
- With no models, the builder offers Models & Providers. Advanced model settings start collapsed and preserve existing overrides when left collapsed.
- Check the longer tab labels and helper text at the minimum window size, with keyboard navigation and VoiceOver.

## Website and updater checks

Run `node Tests/HelpRegression.js` to check knowledge-base files, deep links, search, and navigation without network access. Run `python3 Tests/SparkleRegression.py /path/to/ChatHarbor.app` after building to validate updater settings, bundled helpers, release numbering, and signing-key validation with public test vectors. See [the update guide](../docs/UPDATES.md) for the isolated upgrade rehearsal; never use production app data for it.
