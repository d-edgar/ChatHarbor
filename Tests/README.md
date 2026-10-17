# Regression checks

Run from the repository root with the full Xcode toolchain selected:

```sh
bash Tests/run.sh
```

The checks cover:

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
