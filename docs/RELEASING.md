# Release procedure

## Personal release

Run the tests, media checks, content checks, and `Scripts/build.sh`. Verify `SHA256SUMS` from the output directory and record `SOURCE-SHA256`, the toolchain, and measured acceptance results in `VALIDATION.md`. Install the app in a new folder and verify launch, selected-file access, export, and session recovery. Ad-hoc signing supports local use; a stable Apple Development identity avoids identity changes across rebuilds.

The normal build does not publish anything, contact a notarization service, or use distribution credentials.

## Future distribution

Before distributing binaries to other people:

1. Complete all production acceptance gates for the exact release revision, including natural human speech, three-hour operation, accessibility, first-run and upgrade behavior, and failure recovery.
2. Set a release version and build number, commit reviewed changes, and tag that commit `v<version>`. Keep preceding release artifacts for rollback.
3. Install your Developer ID Application certificate and private key in Keychain. Configure notarization credentials using `xcrun notarytool store-credentials` with an interactive Keychain profile. Never store secrets in the repository.
4. Set `DEVELOPER_ID_IDENTITY`, `DEVELOPMENT_TEAM`, and `NOTARY_KEYCHAIN_PROFILE`, then run `bash Scripts/release.sh`.
5. The script tests the code, archives with hardened runtime, verifies signature properties, notarizes, requires an Accepted result, staples the ticket, and checks Gatekeeper. It creates versioned ZIP and checksum files only after these steps pass.
6. Verify the extracted ZIP on a separate Mac or clean user account, including launch through Gatekeeper, first model installation, offline transcription, file selection, saved-session recovery, and upgrades. Publish only the completed `publish` directory when explicitly authorized.

Signing and notarization scripts are preparation, not evidence of Apple approval. App Store submission would require its own signing, entitlement, privacy, review, and store-material checks. No App Store acceptance is claimed.

Consult Apple's official documentation for [notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) and [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox).
