# Shipping app updates

ChatHarbor uses Sparkle 2.10.0 with automatic daily checks, manual Check for Updates, and user-approved installations only. Settings → General can disable automatic checks. System profiling is disabled. Both the feed and downloaded archive must pass EdDSA verification.

## One-time signing setup

The production signing key was generated in macOS Keychain under the Sparkle account `com.chatharbor.app`. Only its public key is in `ChatHarbor/Info.plist`. Keep a secure backup; do not regenerate it for each release or commit an exported private key.

The matching private key is configured as the repository Actions secret `SPARKLE_PRIVATE_KEY` (2026-10-19). To restore or migrate the secret, use the original key. Use Sparkle's `generate_keys --account com.chatharbor.app -x <private-file>` to export it securely, transfer it to that secret, then remove the temporary export. Do not paste it into logs, issues, or chat. The release workflow derives its public key and fails before building if the secret is absent, malformed, or does not match the app.

## Each release

1. Bump `MARKETING_VERSION` and update the changelog. `CURRENT_PROJECT_VERSION` follows that version so Sparkle can detect a newer build. Never reuse a published version.
2. Run the build, `bash Tests/run.sh`, `node Tests/HelpRegression.js`, and `python3 Tests/SparkleRegression.py <built-app>`.
3. Tag the checked commit. The release workflow signs Sparkle's nested helpers, verifies the version against the tag, builds the DMG, notarizes and staples it, then generates a signed appcast.
4. The release publishes the DMG and `appcast.xml` together. The app reads `https://github.com/d-edgar/ChatHarbor/releases/latest/download/appcast.xml`; no server or separate Pages update is required. Do not mark an older release as Latest or delete the latest feed asset.

The first updater-enabled release requires a manual install for users on v2.3.1 or earlier. Until that release publishes its feed, development builds pointed at the production URL will report an update-check error.

## Isolated upgrade rehearsal

Never test replacement against the installed production app. Use two copies with a unique test bundle identifier, an independent temporary EdDSA key, and a localhost feed. Substitute the same test bundle identifier in both Sparkle sandbox entitlements, and sign both copies plus their nested helpers with the same development certificate. Debug copies also need their embedded Debug dylibs signed.

Give the copies increasing bundle versions. Package the second copy with `ditto -c -k --sequesterRsrc --keepParent`, generate its feed using `generate_appcast --ed-key-file <test-key> --maximum-deltas 0 --download-url-prefix http://127.0.0.1:<port>/ <archives>`, and serve only that directory on localhost. Override the test copies' feed URL and public key before signing; allow local networking only in those test copies.

Create disposable chats and settings in the test app, check for updates, confirm the old version remains until Install is chosen, then Install and Relaunch. Verify the new version and retained data. Test that changing a byte in the signed feed or archive fails verification. Quit the test app and stop its server afterward. This rehearsal checks the installer and data preservation; production notarization is still verified by the release workflow.

### Last local rehearsal — 2026-10-19

- Developer-signed, sandboxed copies with bundle ID `com.chatharbor.upgradetest20261019` upgraded from 1.0 to 1.1 through Sparkle's Install Update and Install and Relaunch buttons.
- A disposable SwiftData harbor, a changed fork-title preference, and the disabled automatic-check setting survived relaunch.
- Manual checking worked with automatic checks disabled; checking after the upgrade reported up to date.
- Modifying the signed feed produced an update-validation error and no installation.
- Debug/Release builds, full regressions, updater bundle validation, and knowledge-base checks passed. Production data and credentials were not used. This was a development-signed local ZIP test, not a newly notarized production DMG release.
