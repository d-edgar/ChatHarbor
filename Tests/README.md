# Decision notes smoke test

With the full Xcode toolchain selected, run from the repository root:

```sh
xcrun swiftc ChatHarbor/Models/BrainstormModels.swift Tests/DecisionNotesSmoke.swift -o /tmp/chatharbor-decision-smoke
/tmp/chatharbor-decision-smoke
```

This checks empty defaults and that decision notes, outcome notes, and their timestamp survive reopening a temporary SwiftData store. It does not test migration from an older application store.

Before releasing, build and run the app in Xcode and check:

- Open an existing session after upgrading; its transcript remains intact.
- Finish a new brainstorm; synthesis requests a decision brief with disagreements and an experiment.
- Save decision and outcome notes, switch sessions, relaunch, and verify the notes remain.
- Export Markdown and PDF and ask a follow-up question; saved notes should be included.
- Compare models with and without matching prices; estimates and unavailable labels should display correctly.

In the development environment used for this change, Swift syntax parsing passed. Compilation and the persistence smoke test were blocked by missing SwiftData compiler macros in the command-line-only toolchain; full app validation remains pending.
